import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class MobileAuthResult {
  final bool isAllowed;
  final String code; // 'ACCESS_GRANTED', 'WEB_VERIFICATION_REQUIRED', 'TRIAL_EXPIRED', etc.
  final String message;
  final Map<String, dynamic>? userData;

  MobileAuthResult({
    required this.isAllowed,
    required this.code,
    required this.message,
    this.userData,
  });
}

class MobileAuthService {
  static final MobileAuthService instance = MobileAuthService._internal();
  MobileAuthService._internal();

  /// Verifies user mobile login gate with instant 7-day free trial grant
  Future<MobileAuthResult> verifyMobileLoginGate({
    required String email,
    String? userId,
    String? provider,
    String? idToken,
  }) async {
    final currentUser = SupasService.instance.client.auth.currentUser;

    // 1. Instant 7-Day Free Trial check using Supabase Auth state
    if (currentUser != null) {
      final meta = currentUser.userMetadata ?? {};
      final createdAt = DateTime.tryParse(currentUser.createdAt);
      
      final bool isWithin7DaysOfSignup = createdAt != null &&
          DateTime.now().difference(createdAt).inHours < (7 * 24);

      final bool isMetadataVerified = meta['is_web_verified'] == true ||
          meta['account_status'] == 'trial_active' ||
          meta['account_status'] == 'active' ||
          meta['pro_tier'] == true;

      String? expiryStr = meta['trial_expires_at']?.toString();
      bool isTrialExpired = false;
      if (expiryStr != null) {
        final expiryDate = DateTime.tryParse(expiryStr);
        if (expiryDate != null && DateTime.now().isAfter(expiryDate)) {
          isTrialExpired = true;
        }
      }

      // Grant instant access for any new account within 7 days or with active trial/paid status
      if ((isWithin7DaysOfSignup || isMetadataVerified) && !isTrialExpired) {
        debugPrint('[MobileAuthService] 7-Day Free Trial Active for $email (Created: ${currentUser.createdAt})');
        return MobileAuthResult(
          isAllowed: true,
          code: 'ACCESS_GRANTED',
          message: '7-Day Free Trial Active',
          userData: {
            'userId': currentUser.id,
            'email': currentUser.email,
            'isWebVerified': true,
          },
        );
      }

      if (isTrialExpired || (createdAt != null && DateTime.now().difference(createdAt).inHours >= (7 * 24) && !isMetadataVerified)) {
        return MobileAuthResult(
          isAllowed: false,
          code: 'TRIAL_EXPIRED',
          message: 'Your 7-day free trial has expired. Please subscribe on our web portal to continue using the app.',
        );
      }
    }

    // 2. Safe Database Table Queries ('users' or 'user_profiles')
    try {
      final targetUserId = userId ?? currentUser?.id;
      if (targetUserId != null) {
        Map<String, dynamic>? userRow;
        try {
          userRow = await SupasService.instance.client
              .from('users')
              .select()
              .eq('id', targetUserId)
              .maybeSingle();
        } catch (_) {
          try {
            userRow = await SupasService.instance.client
                .from('user_profiles')
                .select()
                .eq('user_id', targetUserId)
                .maybeSingle();
          } catch (_) {}
        }

        if (userRow != null) {
          final bool dbVerified = userRow['is_web_verified'] == true ||
              userRow['subscription_status'] == 'ACTIVE' ||
              userRow['subscription_status'] == 'TRIAL_ACTIVE' ||
              userRow['ownership_payment'] == true;

          final String? expStr = userRow['trial_expires_at']?.toString();
          bool dbExpired = false;
          if (expStr != null) {
            final exp = DateTime.tryParse(expStr);
            if (exp != null && DateTime.now().isAfter(exp)) {
              dbExpired = true;
            }
          }

          if (dbVerified && !dbExpired) {
            return MobileAuthResult(
              isAllowed: true,
              code: 'ACCESS_GRANTED',
              message: 'Verified via database',
            );
          }
        }
      }
    } catch (err) {
      debugPrint('[MobileAuthService] DB check error: $err');
    }

    // 3. Fallback for expired trials
    return MobileAuthResult(
      isAllowed: false,
      code: 'WEB_VERIFICATION_REQUIRED',
      message: 'Please complete your initial account registration and verification on our website before accessing the mobile app.',
    );
  }

  /// Triggers OAuth Social Sign-in on Mobile (Google / Apple)
  Future<MobileAuthResult> signInWithSocialProvider(String provider) async {
    try {
      // Trigger Supabase OAuth sign-in flow
      await SupasService.instance.client.auth.signInWithOAuth(
        provider == 'google'
            ? OAuthProvider.google
            : OAuthProvider.apple,
        redirectTo: 'checkbook://login-callback',
      );

      final currentUser = SupasService.instance.client.auth.currentUser;
      if (currentUser != null) {
        return await verifyMobileLoginGate(
          email: currentUser.email ?? '',
          userId: currentUser.id,
          provider: provider,
        );
      }

      return MobileAuthResult(
        isAllowed: false,
        code: 'WEB_VERIFICATION_REQUIRED',
        message: 'Please complete your initial account registration and verification on our website before accessing the mobile app.',
      );
    } catch (e) {
      debugPrint('[Social OAuth Error]: $e');
      return MobileAuthResult(
        isAllowed: false,
        code: 'WEB_VERIFICATION_REQUIRED',
        message: 'Please complete your initial account registration and verification on our website before accessing the mobile app.',
      );
    }
  }
}
