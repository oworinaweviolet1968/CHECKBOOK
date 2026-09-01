import { createClient } from '@supabase/supabase-js';

// Supabase Credentials
const SUPABASE_URL = 'https://jhucvkqwenhyiveqsmtf.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_UrI33FTSf-D4iuMReiqK5g_v7qc1l_-';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Global State
let userProfiles = [];
let filteredProfiles = [];
let currentUserSession = null;

// DOM Elements
const loginScreen = document.getElementById('login-screen');
const dashboardView = document.getElementById('dashboard-view');
const formAdminLogin = document.getElementById('form-admin-login');
const loginError = document.getElementById('login-error');
const btnAdminLogin = document.getElementById('btn-admin-login');
const userEmailLabel = document.getElementById('user-email-label');
const btnLogout = document.getElementById('btn-logout');

const statTotalUsers = document.getElementById('stat-total-users');
const statActiveTrials = document.getElementById('stat-active-trials');
const statPaidLicenses = document.getElementById('stat-paid-licenses');
const statCloudBackups = document.getElementById('stat-cloud-backups');

const userTableBody = document.getElementById('user-table-body');
const userCountBadge = document.getElementById('user-count-badge');
const filterLicenseStatus = document.getElementById('filter-license-status');

const btnRefresh = document.getElementById('btn-refresh');
const btnCreateModal = document.getElementById('btn-create-user-modal');
const btnReleasesModal = document.getElementById('btn-releases-modal');

const modalCreateUser = document.getElementById('modal-create-user');
const btnCloseCreateModal = document.getElementById('btn-close-create-modal');
const btnCancelCreate = document.getElementById('btn-cancel-create');
const formCreateUser = document.getElementById('form-create-user');

const modalReleases = document.getElementById('modal-releases');
const btnCloseReleasesModal = document.getElementById('btn-close-releases-modal');
const formAddRelease = document.getElementById('form-add-release');
const releasesTableBody = document.getElementById('releases-table-body');

const inputCheckbookSearch = document.getElementById('input-checkbook-search');
const btnSearchCheckbook = document.getElementById('btn-search-checkbook');
const searchResultToast = document.getElementById('search-result-toast');

// --- Initialization ---
document.addEventListener('DOMContentLoaded', async () => {
  checkSession();

  // Login Form
  formAdminLogin.addEventListener('submit', handleAdminLogin);
  btnLogout.addEventListener('click', handleLogout);

  // Event Listeners
  btnRefresh.addEventListener('click', () => {
    fetchUserProfiles();
    fetchReleases();
  });

  filterLicenseStatus.addEventListener('change', applyFilters);

  // Modals
  btnCreateModal.addEventListener('click', () => modalCreateUser.classList.remove('hidden'));
  btnCloseCreateModal.addEventListener('click', () => modalCreateUser.classList.add('hidden'));
  btnCancelCreate.addEventListener('click', () => modalCreateUser.classList.add('hidden'));

  btnReleasesModal.addEventListener('click', () => modalReleases.classList.remove('hidden'));
  btnCloseReleasesModal.addEventListener('click', () => modalReleases.classList.add('hidden'));

  // Forms
  formCreateUser.addEventListener('submit', handleCreateUser);
  formAddRelease.addEventListener('submit', handleAddRelease);

  // Search
  btnSearchCheckbook.addEventListener('click', handleCheckbookSearch);
  inputCheckbookSearch.addEventListener('keyup', (e) => {
    if (e.key === 'Enter') handleCheckbookSearch();
    else applyFilters();
  });
});

async function checkSession() {
  const { data } = await supabase.auth.getSession();
  if (data.session) {
    currentUserSession = data.session;
    userEmailLabel.textContent = `Signed in as: ${data.session.user.email}`;
    loginScreen.classList.add('hidden');
    dashboardView.classList.remove('hidden');
    fetchUserProfiles();
    fetchReleases();
  } else {
    loginScreen.classList.remove('hidden');
    dashboardView.classList.add('hidden');
  }
}

async function handleAdminLogin(e) {
  e.preventDefault();
  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;

  loginError.classList.add('hidden');
  btnAdminLogin.disabled = true;
  btnAdminLogin.textContent = 'Authenticating...';

  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (error) throw error;

    currentUserSession = data.session;
    userEmailLabel.textContent = `Signed in as: ${data.session.user.email}`;
    loginScreen.classList.add('hidden');
    dashboardView.classList.remove('hidden');

    fetchUserProfiles();
    fetchReleases();
  } catch (err) {
    console.error('Login error:', err);
    loginError.textContent = `❌ ${err.message || 'Authentication failed'}`;
    loginError.classList.remove('hidden');
  } finally {
    btnAdminLogin.disabled = false;
    btnAdminLogin.textContent = 'Sign In as Admin';
  }
}

async function handleLogout() {
  await supabase.auth.signOut();
  currentUserSession = null;
  loginScreen.classList.remove('hidden');
  dashboardView.classList.add('hidden');
}

// --- Data Fetching ---
async function fetchUserProfiles() {
  userTableBody.innerHTML = `<tr><td colspan="7" class="loading-td"><div class="spinner"></div> Fetching user profiles from Supabase...</td></tr>`;

  try {
    const { data, error } = await supabase
      .from('user_profiles')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) throw error;

    userProfiles = data || [];
    applyFilters();
    updateStats();
  } catch (err) {
    console.error('Error fetching profiles:', err);
    userTableBody.innerHTML = `<tr><td colspan="7" class="loading-td" style="color: #ef4444;">Failed to load user profiles: ${err.message}</td></tr>`;
  }
}

async function fetchReleases() {
  try {
    const { data, error } = await supabase
      .from('app_releases')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) throw error;

    renderReleasesTable(data || []);
  } catch (err) {
    console.error('Error fetching releases:', err);
    releasesTableBody.innerHTML = `<tr><td colspan="4" class="loading-td" style="color: #ef4444;">Failed to load releases</td></tr>`;
  }
}

// --- Stats & Filtering ---
function updateStats() {
  const total = userProfiles.length;
  const now = new Date();

  let trials = 0;
  let paid = 0;
  let backups = 0;

  userProfiles.forEach((u) => {
    const isTrial = u.subscription_status === 'TRIAL_ACTIVE' || (u.trial_expires_at && new Date(u.trial_expires_at) > now);
    if (isTrial) trials++;
    if (u.subscription_status === 'ACTIVE') paid++;
    if (u.subscription_status === 'ACTIVE' && (u.plan_tier === 'OWNERSHIP_CLOUD' || u.plan_tier === 'ENTERPRISE')) backups++;
  });

  statTotalUsers.textContent = total;
  statActiveTrials.textContent = trials;
  statPaidLicenses.textContent = paid;
  statCloudBackups.textContent = backups;
  userCountBadge.textContent = `${filteredProfiles.length} Users`;
}

function applyFilters() {
  const statusFilter = filterLicenseStatus.value;
  const searchTerm = inputCheckbookSearch.value.trim().toLowerCase();
  const now = new Date();

  filteredProfiles = userProfiles.filter((u) => {
    // License Filter
    let matchesStatus = true;
    const isTrial = u.subscription_status === 'TRIAL_ACTIVE' || (u.trial_expires_at && new Date(u.trial_expires_at) > now);
    const isPaid = u.subscription_status === 'ACTIVE';

    if (statusFilter === 'TRIAL' && !isTrial) matchesStatus = false;
    if (statusFilter === 'PAID' && !isPaid) matchesStatus = false;
    if (statusFilter === 'EXPIRED' && (isTrial || isPaid)) matchesStatus = false;

    // Search term
    let matchesSearch = true;
    if (searchTerm) {
      const email = (u.email || '').toLowerCase();
      const checkbook = (u.checkbook_id || '').toLowerCase();
      matchesSearch = email.includes(searchTerm) || checkbook.includes(searchTerm);
    }

    return matchesStatus && matchesSearch;
  });

  renderUserTable();
  userCountBadge.textContent = `${filteredProfiles.length} Users`;
}

// --- Table Rendering ---
function renderUserTable() {
  if (filteredProfiles.length === 0) {
    userTableBody.innerHTML = `<tr><td colspan="7" class="loading-td">No user accounts found matching criteria.</td></tr>`;
    return;
  }

  const rowsHtml = filteredProfiles.map((u) => {
    const checkbook = u.checkbook_id || 'UNASSIGNED';
    const email = u.email || 'N/A';
    const createdAt = u.created_at ? new Date(u.created_at).toLocaleDateString() : 'N/A';
    const now = new Date();

    const isTrialActive = u.subscription_status === 'TRIAL_ACTIVE' || (u.trial_expires_at && new Date(u.trial_expires_at) > now);
    const isPaid = u.subscription_status === 'ACTIVE';
    const hasCloud = u.plan_tier === 'OWNERSHIP_CLOUD' || u.plan_tier === 'ENTERPRISE';

    let trialBadge = `<span class="status-chip status-expired">Trial Expired</span>`;
    if (isTrialActive) {
      const daysLeft = u.trial_expires_at 
        ? Math.max(0, Math.ceil((new Date(u.trial_expires_at) - now) / (1000 * 60 * 60 * 24)))
        : 7;
      trialBadge = `<span class="status-chip status-trial">Trial (${daysLeft}d left)</span>`;
    }

    return `
      <tr>
        <td>
          <strong>${email}</strong>
          <br/><small style="color: var(--text-secondary); font-size: 0.75rem;">ID: ${u.user_id}</small>
        </td>
        <td>
          <span class="badge-checkbook">${checkbook}</span>
        </td>
        <td>${trialBadge}</td>
        <td>
          <label class="toggle-label">
            <input 
              type="checkbox" 
              class="toggle-input toggle-license" 
              data-userid="${u.user_id}" 
              ${isPaid ? 'checked' : ''}
            />
            <span class="toggle-slider"></span>
            <span style="font-size: 0.8rem;">${isPaid ? 'Active License' : 'Inactive'}</span>
          </label>
        </td>
        <td>
          <label class="toggle-label">
            <input 
              type="checkbox" 
              class="toggle-input toggle-backup" 
              data-userid="${u.user_id}" 
              ${hasCloud ? 'checked' : ''}
            />
            <span class="toggle-slider"></span>
            <span style="font-size: 0.8rem;">${hasCloud ? 'Active' : 'Inactive'}</span>
          </label>
        </td>
        <td>${createdAt}</td>
        <td>
          <button class="btn btn-secondary btn-action-backfill" data-userid="${u.user_id}" style="padding: 4px 10px; font-size: 0.75rem;">
            ⚡ Gen ID
          </button>
        </td>
      </tr>
    `;
  }).join('');

  userTableBody.innerHTML = rowsHtml;

  // Add event listeners to toggle switches & backfill buttons
  document.querySelectorAll('.toggle-license').forEach((elem) => {
    elem.addEventListener('change', async (e) => {
      if (!confirm("Are you sure you want to change this user's license status?")) {
        e.target.checked = !e.target.checked;
        return;
      }
      const userId = e.target.getAttribute('data-userid');
      const isChecked = e.target.checked;
      await updateUserLicense(userId, isChecked ? 'ACTIVE' : 'EXPIRED');
    });
  });

  document.querySelectorAll('.toggle-backup').forEach((elem) => {
    elem.addEventListener('change', async (e) => {
      if (!confirm("Are you sure you want to change this user's cloud backup status?")) {
        e.target.checked = !e.target.checked;
        return;
      }
      const userId = e.target.getAttribute('data-userid');
      const isChecked = e.target.checked;
      await updateUserBackup(userId, isChecked ? 'OWNERSHIP_CLOUD' : 'OWNERSHIP_LOCAL');
    });
  });

  document.querySelectorAll('.btn-action-backfill').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      const userId = e.target.getAttribute('data-userid');
      await generateCheckbookIdForUser(userId);
    });
  });
}

function renderReleasesTable(releases) {
  if (releases.length === 0) {
    releasesTableBody.innerHTML = `<tr><td colspan="4" class="loading-td">No app releases published yet.</td></tr>`;
    return;
  }

  releasesTableBody.innerHTML = releases.map((r) => `
    <tr>
      <td><span class="status-chip status-active">${r.platform.toUpperCase()}</span></td>
      <td><strong>${r.version}</strong></td>
      <td><a href="${r.download_url}" target="_blank" style="color: var(--primary-teal-hover); text-decoration: none;">Download Link</a></td>
      <td>${new Date(r.created_at).toLocaleDateString()}</td>
    </tr>
  `).join('');
}

// --- Supabase Actions ---
async function handleCreateUser(e) {
  e.preventDefault();
  const email = document.getElementById('create-email').value.trim();
  const password = document.getElementById('create-password').value;
  const plan = document.getElementById('create-plan').value;

  const btnSubmit = document.getElementById('btn-submit-create');
  btnSubmit.disabled = true;
  btnSubmit.textContent = 'Creating...';

  try {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { plan_tier: plan }
      }
    });

    if (error) throw error;

    alert(`User account created successfully for ${email}!`);
    modalCreateUser.classList.add('hidden');
    formCreateUser.reset();
    fetchUserProfiles();
  } catch (err) {
    alert(`Failed to create user: ${err.message}`);
  } finally {
    btnSubmit.disabled = false;
    btnSubmit.textContent = 'Create Account';
  }
}

async function updateUserLicense(userId, newStatus) {
  const isPaid = newStatus === 'ACTIVE';
  const newPlan = isPaid ? 'OWNERSHIP_CLOUD' : 'FREE';

  // 1. Update in-memory user object immediately for instant UI feedback
  const user = userProfiles.find((u) => u.user_id === userId);
  if (user) {
    user.subscription_status = newStatus;
    user.plan_tier = newPlan;
    user.ownership_payment = isPaid;
    user.has_ownership_license = isPaid;
  }
  updateStats();

  try {
    // 2. Direct database update on user_profiles
    const { error: updateErr } = await supabase
      .from('user_profiles')
      .update({
        subscription_status: newStatus,
        plan_tier: newPlan,
        is_web_verified: isPaid,
        updated_at: new Date().toISOString()
      })
      .eq('user_id', userId);

    if (updateErr) {
      console.warn('Direct update warning, attempting RPC:', updateErr);
      // Try RPC fallback if direct update hits RLS
      const { error: rpcErr } = await supabase.rpc('rpc_admin_toggle_user_license', {
        p_user_id: userId,
        p_status: newStatus
      });
      if (rpcErr && rpcErr.code !== 'PGRST202') throw rpcErr;
    }
  } catch (err) {
    console.error('Failed to persist license update:', err);
  }
}

async function updateUserBackup(userId, newPlan) {
  const isCloud = newPlan === 'OWNERSHIP_CLOUD' || newPlan === 'ENTERPRISE';
  // 1. Update in-memory user object immediately for instant UI feedback
  const user = userProfiles.find((u) => u.user_id === userId);
  if (user) {
    user.plan_tier = newPlan;
    if (isCloud) user.is_web_verified = true;
  }
  updateStats();

  try {
    // 2. Direct database update on user_profiles
    const updatePayload = {
      plan_tier: newPlan,
      updated_at: new Date().toISOString()
    };
    if (isCloud) {
      updatePayload.is_web_verified = true;
    }
    const { error: updateErr } = await supabase
      .from('user_profiles')
      .update(updatePayload)
      .eq('user_id', userId);

    if (updateErr) {
      console.warn('Direct update warning:', updateErr);
      alert('Failed to update cloud backup status. Check console for details.');
    }
  } catch (err) {
    console.error('Failed to persist backup update:', err);
  }
}

async function generateCheckbookIdForUser(userId) {
  const randomId = 'CK-' + Math.floor(100000 + Math.random() * 900000);
  try {
    const { error } = await supabase
      .from('user_profiles')
      .update({ checkbook_id: randomId, updated_at: new Date().toISOString() })
      .eq('user_id', userId);

    if (error) throw error;

    alert(`Generated new Checkbook ID: ${randomId}`);
    fetchUserProfiles();
  } catch (err) {
    alert(`Failed to generate Checkbook ID: ${err.message}`);
  }
}

async function handleCheckbookSearch() {
  const query = inputCheckbookSearch.value.trim();
  if (!query) {
    searchResultToast.classList.add('hidden');
    return;
  }

  searchResultToast.className = 'search-result-toast hidden';
  searchResultToast.textContent = 'Searching...';
  searchResultToast.classList.remove('hidden');

  try {
    const { data, error } = await supabase.rpc('rpc_lookup_user_by_checkbook_id', {
      p_checkbook_id: query
    });

    if (error) throw error;

    if (data && data.found) {
      searchResultToast.className = 'search-result-toast success';
      searchResultToast.innerHTML = `✅ Found! <strong>Checkbook ID: ${data.checkbook_id}</strong> &bull; User Email: <strong>${data.email}</strong>`;
    } else {
      searchResultToast.className = 'search-result-toast error';
      searchResultToast.textContent = `❌ ${data?.message || 'Checkbook ID not found.'}`;
    }
  } catch (err) {
    searchResultToast.className = 'search-result-toast error';
    searchResultToast.textContent = `Error performing RPC lookup: ${err.message}`;
  }
}

async function handleAddRelease(e) {
  e.preventDefault();
  const platform = document.getElementById('rel-platform').value;
  const version = document.getElementById('rel-version').value.trim();
  const download_url = document.getElementById('rel-url').value.trim();
  const release_notes = document.getElementById('rel-notes').value.trim();

  try {
    const { error } = await supabase
      .from('app_releases')
      .insert([{ platform, version, download_url, release_notes }]);

    if (error) throw error;

    alert('New release published successfully!');
    formAddRelease.reset();
    fetchReleases();
  } catch (err) {
    alert(`Failed to publish release: ${err.message}`);
  }
}
