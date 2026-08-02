/**
 * Supabase Admin Password Reset Utility
 *
 * Usage:
 *   SUPABASE_SERVICE_ROLE_KEY="your_service_role_key" node admin_reset_password.js <user_id> <new_password>
 *
 * Example:
 *   SUPABASE_SERVICE_ROLE_KEY="eyJhbG..." node admin_reset_password.js 089827f9-380a-4455-8e4c-7d4204e7874b MyNewPass123!
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://jhucvkqwenhyiveqsmtf.supabase.co';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const userId = process.argv[2] || '089827f9-380a-4455-8e4c-7d4204e7874b';
const newPassword = process.argv[3];

if (!SERVICE_ROLE_KEY) {
  console.error('ERROR: Missing SUPABASE_SERVICE_ROLE_KEY environment variable.');
  console.error('Please set SUPABASE_SERVICE_ROLE_KEY from your Supabase Dashboard -> Project Settings -> API.');
  process.exit(1);
}

if (!newPassword) {
  console.error('ERROR: Missing new password argument.');
  console.log(`Usage: SUPABASE_SERVICE_ROLE_KEY="..." node admin_reset_password.js <user_id> <new_password>`);
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

async function resetPassword() {
  console.log(`Resetting password for user ID: ${userId}...`);

  const { data, error } = await supabase.auth.admin.updateUserById(userId, {
    password: newPassword,
  });

  if (error) {
    console.error('Failed to reset password:', error.message);
    process.exit(1);
  }

  console.log(`Successfully updated password for ${data.user.email} (${data.user.id})!`);
}

resetPassword();
