var ocHistory = ocHistory || {};

// Apply filter based on the input value and update URL query parameters.
ocHistory.applyFilter = function() {
  const filterInput = document.getElementById('_filterInput');
  if (!filterInput) return;

  const filterText = filterInput.value;
  const urlParams = new URLSearchParams(window.location.search);
  urlParams.set('filter', filterText);
  
  window.location.href = `${window.location.pathname}?${urlParams.toString()}`;
};

// Update the status of a batch operation (e.g., CancelJob, DeleteInfo) for selected jobs.
ocHistory.updateStatusBatch = function(action, jobIds) {
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
  modalBody.innerHTML = `Do you want to ${action_str} ${jobCountText}`;

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
};

// Update the batch operations for checked rows (e.g., CancelJob, DeleteInfo).
ocHistory.updateBatch = function(rows) {
  const countId = { checked: [], running: [] };

  rows.forEach(row => {
    const checkbox    = row.querySelector('td input[type="checkbox"]');
    const jobId       = row.getElementsByTagName('td')[1].textContent.trim();
    const statusIndex = row.getElementsByTagName('td').length - 1;
    const status      = row.getElementsByTagName('td')[statusIndex].textContent.trim();

    if (checkbox && checkbox.checked) {
      countId.checked.push(jobId);
      if (status === "Running" || status === "Queued") {
        countId.running.push(jobId);
      }
    }
  });

  // Update batch status for deleting job or info action.
  ocHistory.updateStatusBatch("CancelJob",  countId.running);
  ocHistory.updateStatusBatch("DeleteInfo", countId.checked);
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

// Add event listeners to status radio buttons and update the URL when a selection changes.
document.querySelectorAll('input[name="_historyStatus"]').forEach(radio => {
  radio.addEventListener('change', () => {
    const url = new URL(window.location.href);
    url.searchParams.set('status', radio.value);
    url.searchParams.delete('p');
    window.location.href = url.toString();
  });
});

// Add event listeners to cluster radio buttons and update the URL when a selection changes.
document.querySelectorAll('input[name="_historyCluster"]').forEach(radio => {
  radio.addEventListener('change', () => {
    const url = new URL(window.location.href);
    url.searchParams.set('cluster', radio.value);
    url.searchParams.delete('p');
    window.location.href = url.toString();
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
