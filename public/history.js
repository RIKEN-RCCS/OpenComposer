var ocHistory = ocHistory || {};

// Apply filter based on the input value and update URL query parameters.
ocHistory.applyFilter = function() {
  const filterInput = document.getElementById('_filterInput');
  const filterColumnInput = document.getElementById('_historyFilterColumn');
  const dateRangeInput = document.getElementById('_historyDateRange');
  const filterModeInput = document.querySelector('input[name="filter_mode"]:checked');
  const dateFromInput = document.getElementById('_historyDateFrom');
  const dateToInput = document.getElementById('_historyDateTo');
  const detailButton = document.getElementById('_historyAdvancedToggle');
  const statusInputs = [
    document.getElementById('_historyStatusQueued'),
    document.getElementById('_historyStatusRunning'),
    document.getElementById('_historyStatusCompleted'),
    document.getElementById('_historyStatusCancelled'),
    document.getElementById('_historyStatusFailed'),
    document.getElementById('_historyStatusUnknown')
  ].filter(Boolean);
  if (!filterInput) return;

  const filterText = filterInput.value;
  const statuses = statusInputs
    .filter(input => input.checked)
    .map(input => input.value);
  const urlParams = new URLSearchParams(window.location.search);
  urlParams.set('filter', filterText);
  urlParams.delete('statuses');
  urlParams.delete('filter_column');
  urlParams.delete('date_range');
  urlParams.delete('filter_mode');
  urlParams.delete('date_from');
  urlParams.delete('date_to');
  urlParams.delete('detail_open');
  urlParams.delete('p');

  if (statuses.length > 0) {
    urlParams.set('statuses', statuses.join(' '));
  }
  else {
    urlParams.set('statuses', 'nothing');
  }

  if (filterColumnInput && filterColumnInput.value) {
    urlParams.set('filter_column', filterColumnInput.value);
  }

  if (dateRangeInput && dateRangeInput.value && dateRangeInput.value !== 'all') {
    urlParams.set('date_range', dateRangeInput.value);
  }

  if (filterModeInput && filterModeInput.value && filterModeInput.value !== 'and') {
    urlParams.set('filter_mode', filterModeInput.value);
  }

  if (dateRangeInput && dateRangeInput.value === 'custom' && dateFromInput && dateFromInput.value) {
    urlParams.set('date_from', dateFromInput.value);
  }

  if (dateRangeInput && dateRangeInput.value === 'custom' && dateToInput && dateToInput.value) {
    urlParams.set('date_to', dateToInput.value);
  }

  if (detailButton && detailButton.getAttribute('aria-expanded') === 'true') {
    urlParams.set('detail_open', 'true');
  }

  window.location.href = `${window.location.pathname}?${urlParams.toString()}`;
};

ocHistory.updateDateRangeVisibility = function() {
  const dateRangeInput = document.getElementById('_historyDateRange');
  const customDates = document.getElementById('_historyCustomDates');
  if (!dateRangeInput || !customDates) return;

  customDates.classList.toggle('d-none', dateRangeInput.value !== 'custom');
  ocHistory.syncSearchLabelWidth();
};

ocHistory.syncSearchLabelWidth = function() {
  const labels = Array.from(document.querySelectorAll('.history-search-label'));
  if (labels.length === 0) return;

  labels.forEach(label => {
    label.style.width = 'auto';
  });

  const maxWidth = Math.ceil(Math.max(...labels.map(label => label.offsetWidth)));
  labels.forEach(label => {
    label.style.width = `${maxWidth}px`;
  });
};

// Toggle the detailed search area.
ocHistory.toggleAdvancedSearch = function() {
  const panel = document.getElementById('_historyAdvancedSearch');
  const button = document.getElementById('_historyAdvancedToggle');
  const icon = document.getElementById('_historyAdvancedToggleIcon');
  if (!panel || !button || !icon) return;

  const isHidden = panel.classList.contains('d-none');
  panel.classList.toggle('d-none', !isHidden);
  button.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
  button.classList.toggle('active', isHidden);
  icon.classList.toggle('bi-chevron-down', !isHidden);
  icon.classList.toggle('bi-chevron-up', isHidden);
  window.requestAnimationFrame(() => ocHistory.syncSearchLabelWidth());
};

ocHistory.advancedToggle = document.getElementById('_historyAdvancedToggle');
if (ocHistory.advancedToggle) {
  ocHistory.advancedToggle.addEventListener('click', function() {
    ocHistory.toggleAdvancedSearch();
  });
}

ocHistory.dateRangeInput = document.getElementById('_historyDateRange');
if (ocHistory.dateRangeInput) {
  ocHistory.updateDateRangeVisibility();
  ocHistory.dateRangeInput.addEventListener('change', function() {
    ocHistory.updateDateRangeVisibility();
  });
}

ocHistory.syncSearchLabelWidth();

document.querySelectorAll('input[id^="_historyStatus"]').forEach(input => {
  input.addEventListener('change', function() {
    ocHistory.applyFilter();
  });
});

// Update the status of a batch operation (e.g., CancelJob, DeleteInfo) for selected jobs.
// blockedIds (optional): jobs excluded from the action that the user must cancel first.
ocHistory.updateStatusBatch = function(action, jobIds, blockedIds) {
  if (!Array.isArray(jobIds)) return;

  const button    = document.getElementById(`_history${action}Badge`);
  const count     = document.getElementById(`_history${action}Count`);
  const input     = document.getElementById(`_history${action}Input`);
  const modalBody = document.getElementById(`_history${action}Body`);

  input.value = jobIds.join(',');

  // Enable or disable the action button based on job selection.
  if (jobIds.length > 0) {
    button.classList.remove('disabled');
    button.disabled = false;
  }
  else {
    button.classList.add('disabled');
    button.disabled = true;
  }

  // Update the job count display.
  count.textContent = jobIds.length;

  // Update the modal content.
  const jobCountText = jobIds.length === 1
    ? ` one ${action === 'CancelJob' ? 'job' : 'information'} (Job ID is ${jobIds[0]}) ?`
    : ` ${jobIds.length} ${action === 'CancelJob' ? 'jobs' : 'information'} ?`;

  const action_str = action === 'CancelJob' ? "cancel" : "delete";
  modalBody.innerHTML = jobIds.length > 0
    ? `Do you want to ${action_str} ${jobCountText}`
    : '';

  // If more than one job is selected, display the list of job IDs.
  if (jobIds.length > 1) {
    const jobList = document.createElement('ul');
    jobIds.forEach(jobId => {
      const listItem = document.createElement('li');
      listItem.textContent = jobId;
      jobList.appendChild(listItem);
    });
    modalBody.appendChild(jobList);
  }

  // Show the scancel command that will be run.
  if (action === 'CancelJob' && jobIds.length > 0) {
    const stripArraySuffix = id => id.replace(/\[([^\]]+)\]/g, (_, inner) => '[' + inner.replace(/[:%]\d+/g, '') + ']');
    const prefix  = ocHistory.cancelCommandPrefix || 'scancel';
    const command = prefix + ' ' + jobIds.map(stripArraySuffix).join(' ');
    const details = document.createElement('details');
    details.className = 'mt-2';
    details.innerHTML =
      `<summary class="text-muted small" style="cursor:pointer">Source: scancel <i class="bi bi-chevron-down"></i></summary>` +
      `<pre class="small text-muted mt-1 p-1 mb-0" style="white-space:pre-wrap;word-break:break-all">${ocHistory.escapeHtml(command)}</pre>`;
    modalBody.appendChild(details);
  }

  // Warn about jobs that cannot be deleted because they are active.
  if (action === 'DeleteInfo' && Array.isArray(blockedIds) && blockedIds.length > 0) {
    const noun = blockedIds.length === 1 ? 'job' : 'jobs';
    const warning = document.createElement('div');
    warning.className = 'alert alert-warning mt-2 mb-0';
    warning.innerHTML =
      `<strong>${blockedIds.length} ${noun} cannot be deleted</strong> — ` +
      `they are Running or Queued. Cancel them first, then delete.`;
    modalBody.appendChild(warning);
  }
};

// Update the batch operations for checked rows (e.g., CancelJob, DeleteInfo).
ocHistory.updateBatch = function(rows) {
  const countId = { running: [], deletable: [], blocked: [] };

  rows.forEach(row => {
    const checkbox = row.querySelector('td input[type="checkbox"]');
    const jobId    = row.getElementsByTagName('td')[1].textContent.trim();
    const status   = (row.dataset.status || '').toUpperCase();

    if (checkbox && checkbox.checked) {
      const isActive = (status === 'QUEUED' || status === 'RUNNING');
      if (isActive) {
        countId.running.push(jobId);
        countId.blocked.push(jobId);
      } else {
        countId.deletable.push(jobId);
      }
    }
  });

  // Only deletable (non-active) jobs appear in the delete action.
  // Blocked jobs get a warning in the modal instead.
  ocHistory.updateStatusBatch("CancelJob",  countId.running);
  ocHistory.updateStatusBatch("DeleteInfo", countId.deletable, countId.blocked);
};

// Redirect to the current URL with the selected number of rows as a query parameter.
ocHistory.redirectWithRows = function() {
  const selectBox = document.getElementById("_historyRows");
  if (!selectBox) return;

  const selectedValue = selectBox.value;
  const url = new URL(window.location.href);
  const params = url.searchParams;

  params.delete('p');
  params.set('rows', selectedValue);
  window.location.href = url.toString();
};

// Add event listeners to cluster radio buttons and update the URL when a selection changes.
document.querySelectorAll('input[name="_historyCluster"]').forEach(radio => {
  radio.addEventListener('change', () => {
    const url = new URL(window.location.href);
    const detailButton = document.getElementById('_historyAdvancedToggle');
    url.searchParams.set('cluster', radio.value);
    url.searchParams.delete('p');
    url.searchParams.delete('detail_open');

    if (detailButton && detailButton.getAttribute('aria-expanded') === 'true') {
      url.searchParams.set('detail_open', 'true');
    }

    window.location.href = url.toString();
  });
});


// When the browser restores this page from bfcache (user pressed Back), re-enable
// any Load-parameters buttons that were disabled before navigation.
window.addEventListener('pageshow', function(event) {
  if (event.persisted) {
    document.querySelectorAll('button[onclick*="loadExtScript"]').forEach(function(btn) {
      btn.disabled = false;
      btn.textContent = 'Load script';
    });
  }
});

// Load the script from a "Job Script (Slurm - Generic)" modal into the target
// app via sessionStorage, prefilling the script editor and all three header
// fields (Script location, Script name, Job name) from the metadata stashed by
// loadJobScript.
ocHistory.loadExtScript = function(btn) {
  var modal = btn.closest('.modal');
  if (!modal) return;
  var body = modal.querySelector('.modal-body[data-script-job-id]');
  if (!body) return;

  // Wait until loadJobScript has finished (whether the script was available or not).
  // Without this guard the button click is silently ignored while the spinner is running.
  if (body.dataset.loaded !== 'true') return;

  var pre = body.querySelector('pre');
  var scriptContent = pre ? pre.textContent : '';

  var cluster  = body.dataset.cluster || '';
  var base     = window.location.pathname.replace(/\/history$/, '');
  var formData = new URLSearchParams({ cluster: cluster });

  btn.disabled    = true;
  btn.textContent = 'Loading…';

  fetch(base + '/history/save_external_script', { method: 'POST', body: formData })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.url) {
        var payload = {
          script:         scriptContent,
          scriptLocation: body.dataset.extScriptLocation || '',
          scriptName:     body.dataset.extScriptName     || '',
          jobName:        body.dataset.extJobName        || ''
        };
        var key = '_oc_ext_' + Date.now();
        sessionStorage.setItem(key, JSON.stringify(payload));
        var sep = data.url.indexOf('?') >= 0 ? '&' : '?';
        window.location.href = data.url + sep + 'ocExtLoad=' + encodeURIComponent(key);
      } else {
        alert('Error: ' + (data.error || 'Unknown error'));
        btn.disabled    = false;
        btn.textContent = 'Load script';
      }
    })
    .catch(function(e) {
      alert('Error: ' + e.message);
      btn.disabled    = false;
      btn.textContent = 'Load script';
    });
};

// Escape HTML special characters for safe DOM insertion.
ocHistory.escapeHtml = function(text) {
  const d = document.createElement('div');
  d.textContent = String(text == null ? '' : text);
  return d.innerHTML;
};

// Build HTML table content for Job Details modal from /job_details JSON.
ocHistory.buildJobDetailsContent = function(data) {
  if (data.error) {
    return `<div class="alert alert-warning">${ocHistory.escapeHtml(data.error)}</div>`;
  }

  // Show all scheduler fields in the order returned by the server (sacct/scontrol ordering).
  const rows = data.data ? Object.entries(data.data) : [];

  if (rows.length === 0) {
    let html = '<p class="text-muted">(No details available for this job.)</p>';
    if (data.errors && Object.keys(data.errors).length > 0) {
      html += '<details class="mt-2"><summary class="text-muted small">Error details</summary>';
      Object.entries(data.errors).forEach(([src, msg]) => {
        html += `<p class="text-muted small mb-0"><strong>${ocHistory.escapeHtml(src)}:</strong> ${ocHistory.escapeHtml(msg)}</p>`;
      });
      html += '</details>';
    }
    return html;
  }

  let html = '<table class="table table-striped table-sm text-break">';
  rows.forEach(([k, v]) => {
    html += `<tr><td>${ocHistory.escapeHtml(k)}</td><td>${ocHistory.escapeHtml(v)}</td></tr>`;
  });
  html += '</table>';

  if (data.source && data.source !== 'none') {
    if (data.command) {
      html += `<details class="mt-2"><summary class="text-muted small" style="cursor:pointer">Source: ${ocHistory.escapeHtml(data.source)}</summary><pre class="small text-muted mt-1 p-1 mb-0" style="white-space:pre-wrap;word-break:break-all">${ocHistory.escapeHtml(data.command)}</pre></details>`;
    } else {
      html += `<p class="text-muted small mt-1 mb-0">Source: ${ocHistory.escapeHtml(data.source)}</p>`;
    }
  }
  return html;
};

// Fetch job details from the server and populate the Job Details modal.
ocHistory.loadJobDetails = function(modalEl) {
  const body = modalEl.querySelector('.modal-body[data-job-id]');
  if (!body || body.dataset.loaded === 'true') return;

  const jobId   = body.dataset.jobId;
  const cluster = body.dataset.cluster;
  const base    = window.location.pathname.replace(/\/history$/, '');
  let url = `${base}/job_details?jobId=${encodeURIComponent(jobId)}`;
  if (cluster) url += `&cluster=${encodeURIComponent(cluster)}`;

  fetch(url)
    .then(r => r.json())
    .then(data => {
      body.dataset.loaded = 'true';
      body.innerHTML = ocHistory.buildJobDetailsContent(data);
    })
    .catch(() => {
      body.dataset.loaded = 'true';
      body.innerHTML = '<div class="alert alert-warning">Could not load job details.</div>';
    });
};

// Fetch batch script via sacct -B and populate the Job Script modal.
// Also stashes script_location, script_name, and JobName as data-attributes on
// the modal body so that loadExtScript can prefill the form header fields.
ocHistory.loadJobScript = function(modalEl) {
  const body = modalEl.querySelector('.modal-body[data-script-job-id]');
  if (!body || body.dataset.loaded === 'true') return;

  const jobId   = body.dataset.scriptJobId;
  const cluster = body.dataset.cluster;
  const base    = window.location.pathname.replace(/\/history$/, '');
  let url = `${base}/job_details?jobId=${encodeURIComponent(jobId)}`;
  if (cluster) url += `&cluster=${encodeURIComponent(cluster)}`;

  fetch(url)
    .then(r => r.json())
    .then(data => {
      body.dataset.loaded = 'true';
      // Stash metadata for loadExtScript to use when "Load script" is clicked.
      if (data.script_location) body.dataset.extScriptLocation = data.script_location;
      if (data.script_name)     body.dataset.extScriptName     = data.script_name;
      if (data.data && data.data.JobName) body.dataset.extJobName = data.data.JobName;
      if (data.script_content) {
        body.innerHTML = `<pre class="mb-0 p-2" style="white-space: pre-wrap;">${ocHistory.escapeHtml(data.script_content)}</pre>`;
      } else {
        body.innerHTML = '<p class="text-muted p-2">(No batch script available for this job.)</p>';
      }
    })
    .catch(() => {
      body.dataset.loaded = 'true';
      body.innerHTML = '<div class="alert alert-warning m-2">Could not load batch script.</div>';
    });
};

// Load efficiency data for a terminal job (completed/failed/cancelled).
ocHistory.loadJobEfficiency = function(modalEl) {
  const effRow = document.getElementById(modalEl.id + 'EffRow');
  if (!effRow || effRow.dataset.loaded === 'true') return;

  const body = modalEl.querySelector('.modal-body[data-job-id]');
  if (!body) return;
  const jobId   = body.dataset.jobId;
  const cluster = body.dataset.cluster;
  const base    = window.location.pathname.replace(/\/history$/, '');
  let url = `${base}/history/job_efficiency?job_id=${encodeURIComponent(jobId)}`;
  if (cluster) url += `&cluster=${encodeURIComponent(cluster)}`;

  const noData = '<hr class="mt-0"><h6 class="mb-2">Job Efficiency (<code>seff</code>)</h6><p class="text-muted small mb-0">No efficiency information available.</p>';

  fetch(url)
    .then(r => r.json())
    .then(data => {
      effRow.dataset.loaded = 'true';
      if (data.error || data.status === 'not_available') {
        effRow.innerHTML = noData;
        return;
      }
      const skip = new Set(['status', 'state', 'command']);
      const rows = Object.entries(data)
        .filter(([k]) => !skip.has(k))
        .map(([k, v]) => `<tr><td>${ocHistory.escapeHtml(k)}</td><td>${ocHistory.escapeHtml(String(v))}</td></tr>`)
        .join('');
      let html = '<hr class="mt-0"><h6 class="mb-2">Job Efficiency (<code>seff</code>)</h6>';
      html += '<table class="table table-striped table-sm text-break mb-1">';
      html += rows || `<tr><td colspan="2" class="text-center text-muted">No efficiency information available.</td></tr>`;
      html += '</table>';
      if (data.command) {
        html += `<details class="mt-1"><summary class="text-muted small" style="cursor:pointer">Source: sacct</summary><pre class="small text-muted mt-1 p-1 mb-0" style="white-space:pre-wrap;word-break:break-all">${ocHistory.escapeHtml(data.command)}</pre></details>`;
      }
      effRow.innerHTML = html;
    })
    .catch(() => {
      effRow.dataset.loaded = 'true';
      effRow.innerHTML = noData;
    });
};

// Attach lazy-load listeners to Job Details modals.
document.querySelectorAll('[id^="_historyJobId"]').forEach(function(el) {
  el.addEventListener('show.bs.modal', function() {
    ocHistory.loadJobDetails(this);
    ocHistory.loadJobEfficiency(this);
  });
});

// Attach lazy-load listeners to Job Script modals (when script content is missing from DB).
document.querySelectorAll('[id^="_historyJobScript"]').forEach(function(el) {
  el.addEventListener('show.bs.modal', function() {
    ocHistory.loadJobScript(this);
  });
});

// Handle "Select All" checkbox functionality.
ocHistory.selectAllCheckbox = document.getElementById('_historySelectAll');
ocHistory.tbody = document.getElementById('_historyTbody');

if (ocHistory.selectAllCheckbox && ocHistory.tbody) {
  const rows = Array.from(ocHistory.tbody.getElementsByTagName('tr'));

  // Event listener for the "Select All" checkbox.
  ocHistory.selectAllCheckbox.addEventListener('change', function() {
    const isChecked = this.checked;
    rows.forEach(row => {
      const checkbox = row.querySelector('td input[type="checkbox"]');
      if (checkbox) checkbox.checked = isChecked;
    });
    ocHistory.updateBatch(rows);
  });

  // Event listener for individual row checkboxes.
  rows.forEach(row => {
    const checkbox = row.querySelector('td input[type="checkbox"]');
    if (checkbox) {
      checkbox.addEventListener('change', function() {
        ocHistory.updateBatch(rows);
      });
    }
  });
}

// Expand a single job ID: "6832503_[1000-2000]" → ["6832503_1000", ..., "6832503_2000"].
// Plain IDs are returned as-is in a one-element array.
function ocExpandJobId(jobId) {
  var cleanId = jobId.replace(/%\d+/g, '');
  var m = cleanId.match(/^(\d+)_\[(\d+)-(\d+)(?::(\d+))?\]$/);
  if (!m) return [cleanId];
  var parent = m[1], first = parseInt(m[2], 10), last = parseInt(m[3], 10);
  var step = m[4] ? Math.max(parseInt(m[4], 10), 1) : 1;
  var ids = [];
  for (var i = first; i <= last; i += step) ids.push(parent + '_' + i);
  return ids;
}

// Expand an array of job IDs, flattening any bracket-range entries.
function ocExpandJobIds(ids) {
  var out = [];
  for (var i = 0; i < ids.length; i++) {
    var exp = ocExpandJobId(ids[i]);
    for (var j = 0; j < exp.length; j++) out.push(exp[j]);
  }
  return out;
}

// Cancel jobs one-by-one, showing a progress bar and Abort button in the CancelJob modal.
ocHistory.cancelJobsOneByOne = async function(jobIds, cluster) {
  var modal    = document.getElementById('_historyCancelJob');
  var body     = document.getElementById('_historyCancelJobBody');
  var form     = document.getElementById('_historyCancelJobForm');
  var abortBtn = document.getElementById('_historyCancelJobAbortBtn');
  var closeBtn = document.getElementById('_historyCancelJobCloseBtn');
  if (!modal || !body) return;

  var total   = jobIds.length;
  var done    = 0;
  var errors  = [];
  var aborted = false;

  // Hide form buttons, show Abort.
  if (form)     form.classList.add('d-none');
  if (abortBtn) { abortBtn.classList.remove('d-none'); abortBtn.disabled = false; abortBtn.textContent = 'Abort'; }
  if (closeBtn) closeBtn.classList.add('d-none');

  body.innerHTML =
    '<div class="mb-2">Cancelling ' + total + ' job' + (total !== 1 ? 's' : '') + '...</div>' +
    '<div class="progress mb-2" style="height:1.4rem;">' +
      '<div id="_ocCancelBar" class="progress-bar progress-bar-striped progress-bar-animated bg-warning"' +
           ' role="progressbar" style="width:0%;min-width:2.5rem;"' +
           ' aria-valuenow="0" aria-valuemin="0" aria-valuemax="100">' +
        '0 / ' + total +
      '</div>' +
    '</div>' +
    '<div id="_ocCancelStatus" class="small text-muted"></div>';

  if (abortBtn) {
    abortBtn.onclick = function() {
      aborted = true;
      abortBtn.disabled    = true;
      abortBtn.textContent = 'Aborting…';
    };
  }

  var base = window.location.pathname.replace(/\/history$/, '');

  for (var i = 0; i < jobIds.length; i++) {
    if (aborted) break;

    var jobId    = jobIds[i];
    var statusEl = document.getElementById('_ocCancelStatus');
    if (statusEl) statusEl.textContent = 'Cancelling ' + jobId + '…';

    try {
      var fd = new URLSearchParams({ jobId: jobId });
      if (cluster) fd.set('cluster', cluster);
      var r    = await fetch(base + '/history/cancel_one', { method: 'POST', body: fd });
      var data = await r.json();
      if (!data.ok) errors.push(jobId + ': ' + (data.error || 'Unknown error'));
    } catch (e) {
      errors.push(jobId + ': ' + e.message);
    }

    done++;
    var pct = Math.round((done / total) * 100);
    var bar = document.getElementById('_ocCancelBar');
    if (bar) {
      bar.style.width = pct + '%';
      bar.textContent = done + ' / ' + total;
      bar.setAttribute('aria-valuenow', pct);
    }
  }

  // Hide Abort, show Close.
  if (abortBtn) abortBtn.classList.add('d-none');
  if (closeBtn) closeBtn.classList.remove('d-none');

  var bar      = document.getElementById('_ocCancelBar');
  var statusEl = document.getElementById('_ocCancelStatus');

  if (aborted) {
    if (bar) { bar.classList.remove('progress-bar-animated', 'bg-warning'); }
    var remaining = total - done;
    if (statusEl) {
      statusEl.innerHTML = '<span class="text-warning fw-semibold">Aborted. ' +
        done + ' of ' + total + ' job' + (total !== 1 ? 's' : '') + ' cancelled; ' +
        remaining + ' remaining.</span>' +
        (errors.length > 0
          ? '<ul class="mb-0 mt-1">' + errors.map(function(e) { return '<li>' + ocHistory.escapeHtml(e) + '</li>'; }).join('') + '</ul>'
          : '');
    }
  } else if (errors.length === 0) {
    if (bar) { bar.classList.remove('progress-bar-animated', 'bg-warning'); bar.classList.add('bg-success'); }
    if (statusEl) statusEl.innerHTML = '<span class="text-success fw-semibold">All jobs cancelled successfully.</span>';
    setTimeout(function() { window.location.reload(); }, 1000);
  } else {
    if (bar) { bar.classList.remove('progress-bar-animated'); }
    if (statusEl) {
      statusEl.innerHTML = '<span class="text-danger fw-semibold">Errors occurred:</span>' +
        '<ul class="mb-0 mt-1">' +
        errors.map(function(e) { return '<li>' + ocHistory.escapeHtml(e) + '</li>'; }).join('') +
        '</ul>';
    }
  }
};

// Reset the CancelJob modal to its initial state (form visible, Abort/Close hidden) each time it closes.
(function() {
  var modal = document.getElementById('_historyCancelJob');
  if (!modal) return;
  modal.addEventListener('hidden.bs.modal', function() {
    var form     = document.getElementById('_historyCancelJobForm');
    var abortBtn = document.getElementById('_historyCancelJobAbortBtn');
    var closeBtn = document.getElementById('_historyCancelJobCloseBtn');
    if (form)     form.classList.remove('d-none');
    if (abortBtn) { abortBtn.classList.add('d-none'); abortBtn.disabled = false; abortBtn.textContent = 'Abort'; }
    if (closeBtn) closeBtn.classList.add('d-none');
  });
})();

// Cancel ALL queued/running jobs one-by-one with an Abort option.
ocHistory.startCancelAll = function() {
  var phase1      = document.getElementById('_cancelAllPhase1');
  var phase2      = document.getElementById('_cancelAllPhase2');
  var progressArea = document.getElementById('_cancelAllProgressArea');
  var abortBtn    = document.getElementById('_cancelAllAbortBtn');
  var closeBtn    = document.getElementById('_cancelAllCloseBtn');
  if (!phase1 || !phase2 || !progressArea || !abortBtn || !closeBtn) return;

  phase1.classList.add('d-none');
  phase2.classList.remove('d-none');

  var base    = window.location.pathname.replace(/\/history$/, '');
  var cluster = new URLSearchParams(window.location.search).get('cluster');

  progressArea.innerHTML = '<p class="text-muted mb-0">Fetching active jobs…</p>';
  abortBtn.disabled  = false;
  abortBtn.textContent = 'Abort';
  abortBtn.classList.remove('d-none');
  closeBtn.classList.add('d-none');

  var url = base + '/history/active_job_ids';
  if (cluster) url += '?cluster=' + encodeURIComponent(cluster);

  fetch(url)
    .then(function(r) { return r.json(); })
    .then(function(jobIds) {
      jobIds = (jobIds || []).slice().reverse();
      if (!jobIds || jobIds.length === 0) {
        progressArea.innerHTML = '<p class="text-muted mb-0">No queued or running jobs found.</p>';
        abortBtn.classList.add('d-none');
        closeBtn.classList.remove('d-none');
        return;
      }

      var total   = jobIds.length;
      var done    = 0;
      var errors  = [];
      var aborted = false;

      progressArea.innerHTML =
        '<div class="mb-2">Cancelling ' + total + ' job' + (total !== 1 ? 's' : '') + '…</div>' +
        '<div class="progress mb-2" style="height:1.4rem;">' +
          '<div id="_cancelAllBar" class="progress-bar progress-bar-striped progress-bar-animated bg-warning"' +
               ' role="progressbar" style="width:0%;min-width:2.5rem;"' +
               ' aria-valuenow="0" aria-valuemin="0" aria-valuemax="100">0 / ' + total + '</div>' +
        '</div>' +
        '<div id="_cancelAllStatus" class="small text-muted"></div>';

      abortBtn.onclick = function() {
        aborted = true;
        abortBtn.disabled    = true;
        abortBtn.textContent = 'Aborting…';
      };

      (async function() {
        for (var i = 0; i < jobIds.length; i++) {
          if (aborted) break;

          var jobId    = jobIds[i];
          var statusEl = document.getElementById('_cancelAllStatus');
          if (statusEl) statusEl.textContent = 'Cancelling ' + jobId + '…';

          try {
            var fd = new URLSearchParams({ jobId: jobId });
            if (cluster) fd.set('cluster', cluster);
            var r    = await fetch(base + '/history/cancel_one', { method: 'POST', body: fd });
            var data = await r.json();
            if (!data.ok) errors.push(jobId + ': ' + (data.error || 'Unknown error'));
          } catch (e) {
            errors.push(jobId + ': ' + e.message);
          }

          done++;
          var pct = Math.round((done / total) * 100);
          var bar = document.getElementById('_cancelAllBar');
          if (bar) {
            bar.style.width = pct + '%';
            bar.textContent = done + ' / ' + total;
            bar.setAttribute('aria-valuenow', pct);
          }
        }

        abortBtn.classList.add('d-none');
        closeBtn.classList.remove('d-none');

        var bar      = document.getElementById('_cancelAllBar');
        var statusEl = document.getElementById('_cancelAllStatus');

        if (aborted) {
          if (bar) { bar.classList.remove('progress-bar-animated', 'bg-warning'); }
          var remaining = total - done;
          if (statusEl) {
            statusEl.innerHTML = '<span class="text-warning fw-semibold">Aborted. ' +
              done + ' of ' + total + ' job' + (total !== 1 ? 's' : '') + ' cancelled; ' +
              remaining + ' remaining.</span>' +
              (errors.length > 0
                ? '<ul class="mb-0 mt-1">' + errors.map(function(e) { return '<li>' + ocHistory.escapeHtml(e) + '</li>'; }).join('') + '</ul>'
                : '');
          }
        } else if (errors.length === 0) {
          if (bar) { bar.classList.remove('progress-bar-animated', 'bg-warning'); bar.classList.add('bg-success'); }
          if (statusEl) statusEl.innerHTML = '<span class="text-success fw-semibold">All jobs cancelled successfully.</span>';
          setTimeout(function() { window.location.reload(); }, 1000);
        } else {
          if (bar) { bar.classList.remove('progress-bar-animated'); }
          if (statusEl) {
            statusEl.innerHTML = '<span class="text-danger fw-semibold">Some errors occurred:</span>' +
              '<ul class="mb-0 mt-1">' + errors.map(function(e) { return '<li>' + ocHistory.escapeHtml(e) + '</li>'; }).join('') + '</ul>';
          }
        }
      })();
    })
    .catch(function(e) {
      progressArea.innerHTML = '<div class="alert alert-warning mb-0">Could not fetch active jobs: ' + ocHistory.escapeHtml(e.message) + '</div>';
      abortBtn.classList.add('d-none');
      closeBtn.classList.remove('d-none');
    });
};

// Reset the CancelAll modal to phase 1 each time it is closed.
(function() {
  var modal = document.getElementById('_historyCancelAll');
  if (!modal) return;
  modal.addEventListener('hidden.bs.modal', function() {
    var phase1   = document.getElementById('_cancelAllPhase1');
    var phase2   = document.getElementById('_cancelAllPhase2');
    var abortBtn = document.getElementById('_cancelAllAbortBtn');
    var closeBtn = document.getElementById('_cancelAllCloseBtn');
    if (phase1)   phase1.classList.remove('d-none');
    if (phase2)   phase2.classList.add('d-none');
    if (abortBtn) { abortBtn.disabled = false; abortBtn.textContent = 'Abort'; abortBtn.classList.remove('d-none'); }
    if (closeBtn) closeBtn.classList.add('d-none');
  });
})();

// Remove error_msg from the URL after the banner has rendered so a manual refresh doesn't re-show it.
(function() {
  var url = new URL(window.location.href);
  if (url.searchParams.has('error_msg')) {
    url.searchParams.delete('error_msg');
    history.replaceState(null, '', url.toString());
  }
})();

var _ocCancelForm = document.getElementById('_historyCancelJobForm');
if (_ocCancelForm) {
  _ocCancelForm.addEventListener('submit', function(e) {
    e.preventDefault();
    var input  = document.getElementById('_historyCancelJobInput');
    var jobIds = (input && input.value) ? input.value.split(',').filter(Boolean).reverse() : [];
    if (!jobIds.length) return;
    var cluster = new URLSearchParams(window.location.search).get('cluster');
    ocHistory.cancelJobsOneByOne(jobIds, cluster);
  });
}

// Open the file content overlay and lazy-load the file at the given path.
ocHistory.openFileOverlay = function(path) {
  const modal = document.getElementById('_historyFileOverlay');
  const title = document.getElementById('_historyFileOverlayTitle');
  const body  = document.getElementById('_historyFileOverlayBody');

  title.textContent = path;
  body.innerHTML = '<div class="text-center py-3"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading…</span></div></div>';

  bootstrap.Modal.getOrCreateInstance(modal).show();

  const base = window.location.pathname.replace(/\/history$/, '');
  fetch(`${base}/_read_file?path=${encodeURIComponent(path)}`)
    .then(r => r.json())
    .then(data => {
      body.innerHTML = '';
      if (data.error) {
        body.innerHTML = `<div class="alert alert-danger m-2">${ocHistory.escapeHtml(data.error)}</div>`;
        return;
      }
      if (data.empty) {
        body.innerHTML = '<p class="text-muted p-3 mb-0">(File is empty)</p>';
        return;
      }
      if (data.truncated) {
        const warn = document.createElement('div');
        warn.className = 'alert alert-warning mx-2 mt-2 mb-0';
        warn.textContent = 'File is large — showing first 1 MB only.';
        body.appendChild(warn);
      }
      const pre = document.createElement('pre');
      pre.className = 'mb-0 p-2';
      pre.style.whiteSpace = 'pre-wrap';
      pre.style.wordBreak = 'break-all';
      pre.textContent = data.content;
      body.appendChild(pre);
    })
    .catch(e => {
      body.innerHTML = `<div class="alert alert-danger m-2">Failed to load file: ${ocHistory.escapeHtml(e.message)}</div>`;
    });
};
