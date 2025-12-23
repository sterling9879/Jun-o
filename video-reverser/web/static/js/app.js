/**
 * Video Reverser - Frontend Application
 * Handles file upload, video management, and processing
 */

// DOM Elements
const dropzone = document.getElementById('dropzone');
const fileInput = document.getElementById('fileInput');
const uploadProgress = document.getElementById('uploadProgress');
const uploadProgressFill = document.getElementById('uploadProgressFill');
const uploadProgressText = document.getElementById('uploadProgressText');

const statsBar = document.getElementById('statsBar');
const statCount = document.getElementById('statCount');
const statSize = document.getElementById('statSize');
const statDuration = document.getElementById('statDuration');
const statSequence = document.getElementById('statSequence');

const sequenceWarning = document.getElementById('sequenceWarning');
const missingNumbers = document.getElementById('missingNumbers');

const emptyState = document.getElementById('emptyState');
const videosTable = document.getElementById('videosTable');
const videosTableBody = document.getElementById('videosTableBody');

const refreshBtn = document.getElementById('refreshBtn');
const clearAllBtn = document.getElementById('clearAllBtn');

const outputName = document.getElementById('outputName');
const optReencode = document.getElementById('optReencode');
const optForce = document.getElementById('optForce');
const processBtn = document.getElementById('processBtn');

const processingStatus = document.getElementById('processingStatus');
const processingStep = document.getElementById('processingStep');
const processingPercent = document.getElementById('processingPercent');
const processingProgressFill = document.getElementById('processingProgressFill');
const processingMessage = document.getElementById('processingMessage');

const processingResult = document.getElementById('processingResult');
const resultSuccess = document.getElementById('resultSuccess');
const resultStats = document.getElementById('resultStats');
const downloadBtn = document.getElementById('downloadBtn');
const resultError = document.getElementById('resultError');
const errorMessage = document.getElementById('errorMessage');

const outputsList = document.getElementById('outputsList');
const outputsEmpty = document.getElementById('outputsEmpty');

const toastContainer = document.getElementById('toastContainer');

// State
let currentVideos = [];
let currentOutputFile = '';
let statusPollInterval = null;

// ============================================
// Toast Notifications
// ============================================

function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;

    const icon = type === 'success'
        ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>'
        : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line></svg>';

    toast.innerHTML = `${icon}<span class="toast-message">${message}</span>`;
    toastContainer.appendChild(toast);

    setTimeout(() => {
        toast.style.animation = 'slideIn 0.3s ease reverse';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// ============================================
// API Functions
// ============================================

async function fetchVideos() {
    try {
        const response = await fetch('/api/videos');
        const data = await response.json();
        currentVideos = data.videos;
        updateVideosUI(data);
    } catch (error) {
        console.error('Error fetching videos:', error);
        showToast('Erro ao carregar videos', 'error');
    }
}

async function uploadFiles(files) {
    const formData = new FormData();

    for (const file of files) {
        formData.append('files', file);
    }

    uploadProgress.hidden = false;
    uploadProgressFill.style.width = '0%';
    uploadProgressText.textContent = 'Enviando...';

    try {
        const xhr = new XMLHttpRequest();

        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                const percent = Math.round((e.loaded / e.total) * 100);
                uploadProgressFill.style.width = `${percent}%`;
                uploadProgressText.textContent = `Enviando... ${percent}%`;
            }
        });

        await new Promise((resolve, reject) => {
            xhr.onload = () => resolve(xhr);
            xhr.onerror = () => reject(new Error('Upload failed'));
            xhr.open('POST', '/api/upload');
            xhr.send(formData);
        });

        const data = JSON.parse(xhr.responseText);

        if (data.uploaded && data.uploaded.length > 0) {
            showToast(`${data.uploaded.length} video(s) enviado(s)`, 'success');
        }

        if (data.errors && data.errors.length > 0) {
            data.errors.forEach(err => {
                showToast(`Erro: ${err.file} - ${err.error}`, 'error');
            });
        }

        await fetchVideos();

    } catch (error) {
        console.error('Upload error:', error);
        showToast('Erro no upload', 'error');
    } finally {
        setTimeout(() => {
            uploadProgress.hidden = true;
        }, 1000);
    }
}

async function deleteVideo(filename) {
    try {
        const response = await fetch(`/api/delete/${encodeURIComponent(filename)}`, {
            method: 'DELETE'
        });

        if (response.ok) {
            showToast(`${filename} removido`, 'success');
            await fetchVideos();
        } else {
            showToast('Erro ao remover video', 'error');
        }
    } catch (error) {
        console.error('Delete error:', error);
        showToast('Erro ao remover video', 'error');
    }
}

async function clearAllVideos() {
    if (!confirm('Remover todos os videos da fila?')) return;

    try {
        const response = await fetch('/api/clear', { method: 'POST' });
        const data = await response.json();

        if (data.success) {
            showToast(`${data.deleted} video(s) removido(s)`, 'success');
            await fetchVideos();
        }
    } catch (error) {
        console.error('Clear error:', error);
        showToast('Erro ao limpar videos', 'error');
    }
}

async function startProcessing() {
    const options = {
        output_name: outputName.value || 'final.mp4',
        reencode: optReencode.checked,
        force: optForce.checked
    };

    try {
        const response = await fetch('/api/process', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(options)
        });

        const data = await response.json();

        if (response.ok) {
            showProcessingUI();
            startStatusPolling();
        } else {
            showToast(data.error || 'Erro ao iniciar processamento', 'error');
        }
    } catch (error) {
        console.error('Process error:', error);
        showToast('Erro ao iniciar processamento', 'error');
    }
}

async function fetchStatus() {
    try {
        const response = await fetch('/api/status');
        const data = await response.json();
        updateProcessingUI(data);
        return data;
    } catch (error) {
        console.error('Status error:', error);
        return null;
    }
}

async function fetchOutputs() {
    try {
        const response = await fetch('/api/outputs');
        const data = await response.json();
        updateOutputsUI(data.outputs);
    } catch (error) {
        console.error('Outputs error:', error);
    }
}

async function deleteOutput(filename) {
    try {
        const response = await fetch(`/api/delete-output/${encodeURIComponent(filename)}`, {
            method: 'DELETE'
        });

        if (response.ok) {
            showToast(`${filename} removido`, 'success');
            await fetchOutputs();
        }
    } catch (error) {
        console.error('Delete output error:', error);
    }
}

// ============================================
// UI Update Functions
// ============================================

function updateVideosUI(data) {
    const { videos, count, total_size, total_duration, sequence_complete, missing_numbers } = data;

    if (count === 0) {
        emptyState.hidden = false;
        videosTable.hidden = true;
        statsBar.hidden = true;
        sequenceWarning.hidden = true;
        processBtn.disabled = true;
        return;
    }

    emptyState.hidden = true;
    videosTable.hidden = false;
    statsBar.hidden = false;
    processBtn.disabled = false;

    // Update stats
    statCount.textContent = count;
    statSize.textContent = total_size;
    statDuration.textContent = total_duration;

    if (sequence_complete) {
        statSequence.textContent = 'Completa';
        statSequence.style.color = 'var(--success)';
        sequenceWarning.hidden = true;
    } else {
        statSequence.textContent = 'Incompleta';
        statSequence.style.color = 'var(--warning)';
        sequenceWarning.hidden = false;
        missingNumbers.textContent = `Faltando: ${missing_numbers.join(', ')}`;
    }

    // Update table
    videosTableBody.innerHTML = videos.map((video, index) => `
        <tr>
            <td class="file-meta">${index + 1}</td>
            <td class="file-name">${video.name}</td>
            <td class="file-meta">${video.duration_formatted}</td>
            <td class="file-meta">${video.size_formatted}</td>
            <td class="file-meta">${video.resolution}</td>
            <td>
                <button class="btn btn-icon" onclick="deleteVideo('${video.name}')" title="Remover">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="3 6 5 6 21 6"></polyline>
                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                    </svg>
                </button>
            </td>
        </tr>
    `).join('');
}

function showProcessingUI() {
    processBtn.disabled = true;
    processingStatus.hidden = false;
    processingResult.hidden = true;
    resultSuccess.hidden = true;
    resultError.hidden = true;
    processingProgressFill.style.width = '0%';
}

function updateProcessingUI(data) {
    if (!data) return;

    const { is_processing, progress, current_step, message, error, result } = data;

    processingProgressFill.style.width = `${progress}%`;
    processingPercent.textContent = `${progress}%`;
    processingMessage.textContent = message;

    // Update step label
    const stepLabels = {
        'scanning': 'Escaneando videos',
        'validating': 'Validando sequencia',
        'reversing': 'Gerando ordem inversa',
        'concatenating': 'Concatenando videos',
        'finishing': 'Finalizando',
        'completed': 'Concluido',
        'error': 'Erro'
    };
    processingStep.textContent = stepLabels[current_step] || current_step;

    if (!is_processing) {
        stopStatusPolling();
        processingStatus.hidden = true;
        processingResult.hidden = false;

        if (error) {
            resultError.hidden = false;
            resultSuccess.hidden = true;
            errorMessage.textContent = error;
            processBtn.disabled = false;
        } else if (result && result.success) {
            resultSuccess.hidden = false;
            resultError.hidden = true;
            currentOutputFile = result.output_file;

            resultStats.innerHTML = `
                <div class="stat-item">
                    <strong>Videos</strong>
                    <span>${result.videos_processed}</span>
                </div>
                <div class="stat-item">
                    <strong>Tamanho</strong>
                    <span>${result.size}</span>
                </div>
                <div class="stat-item">
                    <strong>Duracao</strong>
                    <span>${result.duration}</span>
                </div>
                <div class="stat-item">
                    <strong>Tempo</strong>
                    <span>${result.elapsed}</span>
                </div>
            `;

            fetchOutputs();
            processBtn.disabled = false;
        }
    }
}

function updateOutputsUI(outputs) {
    if (!outputs || outputs.length === 0) {
        outputsEmpty.hidden = false;
        outputsEmpty.nextElementSibling?.remove();
        return;
    }

    outputsEmpty.hidden = true;

    // Remove existing items
    const existingItems = outputsList.querySelectorAll('.output-item');
    existingItems.forEach(item => item.remove());

    outputs.forEach(output => {
        const item = document.createElement('div');
        item.className = 'output-item';
        item.innerHTML = `
            <div class="output-info">
                <span class="output-name">${output.name}</span>
                <span class="output-meta">${output.size} | ${output.duration} | ${output.created}</span>
            </div>
            <div class="output-actions">
                <a href="/api/download/${encodeURIComponent(output.name)}" class="btn btn-primary btn-sm">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="7 10 12 15 17 10"></polyline>
                        <line x1="12" y1="15" x2="12" y2="3"></line>
                    </svg>
                    Baixar
                </a>
                <button class="btn btn-danger btn-sm" onclick="deleteOutput('${output.name}')">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="3 6 5 6 21 6"></polyline>
                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                    </svg>
                </button>
            </div>
        `;
        outputsList.appendChild(item);
    });
}

// ============================================
// Status Polling
// ============================================

function startStatusPolling() {
    stopStatusPolling();
    statusPollInterval = setInterval(fetchStatus, 1000);
}

function stopStatusPolling() {
    if (statusPollInterval) {
        clearInterval(statusPollInterval);
        statusPollInterval = null;
    }
}

// ============================================
// Event Listeners
// ============================================

// Dropzone click
dropzone.addEventListener('click', () => fileInput.click());

// File input change
fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
        uploadFiles(e.target.files);
        fileInput.value = '';
    }
});

// Drag and drop
dropzone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropzone.classList.add('dragover');
});

dropzone.addEventListener('dragleave', () => {
    dropzone.classList.remove('dragover');
});

dropzone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropzone.classList.remove('dragover');

    if (e.dataTransfer.files.length > 0) {
        uploadFiles(e.dataTransfer.files);
    }
});

// Refresh button
refreshBtn.addEventListener('click', () => {
    fetchVideos();
    fetchOutputs();
});

// Clear all button
clearAllBtn.addEventListener('click', clearAllVideos);

// Process button
processBtn.addEventListener('click', startProcessing);

// Download button
downloadBtn.addEventListener('click', () => {
    if (currentOutputFile) {
        window.location.href = `/api/download/${encodeURIComponent(currentOutputFile)}`;
    }
});

// ============================================
// Initialization
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    fetchVideos();
    fetchOutputs();

    // Check for ongoing processing
    fetchStatus().then(data => {
        if (data && data.is_processing) {
            showProcessingUI();
            startStatusPolling();
        }
    });
});

// Make functions globally available
window.deleteVideo = deleteVideo;
window.deleteOutput = deleteOutput;
