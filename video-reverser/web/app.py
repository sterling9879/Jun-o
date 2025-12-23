#!/usr/bin/env python3
"""
Video Reverser - Web Interface Backend
Flask application for managing video concatenation in reverse order
"""

import os
import re
import json
import subprocess
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_file, Response
from werkzeug.utils import secure_filename

# Configuration
BASE_DIR = Path(__file__).parent.parent
INPUT_DIR = BASE_DIR / "input"
OUTPUT_DIR = BASE_DIR / "output"
UPLOAD_DIR = INPUT_DIR
ALLOWED_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv'}
MAX_CONTENT_LENGTH = 16 * 1024 * 1024 * 1024  # 16GB max

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH
app.config['UPLOAD_FOLDER'] = str(UPLOAD_DIR)
app.secret_key = os.urandom(24)

# Global state for processing
processing_status = {
    'is_processing': False,
    'progress': 0,
    'current_step': '',
    'message': '',
    'error': None,
    'result': None,
    'start_time': None,
    'videos_count': 0
}

def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_video_info(filepath):
    """Get video duration and size using ffprobe"""
    try:
        result = subprocess.run([
            'ffprobe', '-v', 'quiet',
            '-print_format', 'json',
            '-show_format', '-show_streams',
            str(filepath)
        ], capture_output=True, text=True)

        if result.returncode == 0:
            data = json.loads(result.stdout)
            duration = float(data.get('format', {}).get('duration', 0))
            size = int(data.get('format', {}).get('size', 0))

            # Get resolution from video stream
            width, height = 0, 0
            for stream in data.get('streams', []):
                if stream.get('codec_type') == 'video':
                    width = stream.get('width', 0)
                    height = stream.get('height', 0)
                    break

            return {
                'duration': duration,
                'size': size,
                'width': width,
                'height': height
            }
    except Exception as e:
        print(f"Error getting video info: {e}")

    return {'duration': 0, 'size': 0, 'width': 0, 'height': 0}

def format_duration(seconds):
    """Format seconds to HH:MM:SS"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"

def format_size(bytes_size):
    """Format bytes to human readable"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024
    return f"{bytes_size:.2f} PB"

def scan_videos():
    """Scan input directory for video files"""
    videos = []

    if not INPUT_DIR.exists():
        INPUT_DIR.mkdir(parents=True, exist_ok=True)
        return videos

    for ext in ALLOWED_EXTENSIONS:
        videos.extend(INPUT_DIR.glob(f"*.{ext}"))
        videos.extend(INPUT_DIR.glob(f"*.{ext.upper()}"))

    # Sort by name (numerical)
    videos = sorted(set(videos), key=lambda x: x.name)

    result = []
    for video in videos:
        info = get_video_info(video)
        result.append({
            'name': video.name,
            'path': str(video),
            'size': info['size'],
            'size_formatted': format_size(info['size']),
            'duration': info['duration'],
            'duration_formatted': format_duration(info['duration']),
            'resolution': f"{info['width']}x{info['height']}" if info['width'] else 'N/A'
        })

    return result

def detect_sequence_gaps(videos):
    """Detect gaps in video numbering sequence"""
    if not videos:
        return [], True

    # Extract numbers from filenames
    numbers = []
    pattern = re.compile(r'^(\d+)')

    for video in videos:
        match = pattern.match(video['name'])
        if match:
            numbers.append(int(match.group(1)))

    if not numbers:
        return [], True

    numbers.sort()
    missing = []

    for i in range(min(numbers), max(numbers)):
        if i not in numbers:
            missing.append(i)

    return missing, len(missing) == 0

def process_videos_thread(output_name, reencode, force):
    """Background thread for video processing"""
    global processing_status

    try:
        processing_status['is_processing'] = True
        processing_status['progress'] = 0
        processing_status['error'] = None
        processing_status['result'] = None
        processing_status['start_time'] = time.time()

        # Step 1: Scan videos
        processing_status['current_step'] = 'scanning'
        processing_status['message'] = 'Escaneando videos...'

        videos = scan_videos()
        if not videos:
            raise Exception("Nenhum video encontrado na pasta input/")

        processing_status['videos_count'] = len(videos)
        processing_status['progress'] = 10

        # Step 2: Validate sequence
        processing_status['current_step'] = 'validating'
        processing_status['message'] = 'Validando sequencia...'

        missing, is_complete = detect_sequence_gaps(videos)
        if not is_complete and not force:
            raise Exception(f"Sequencia incompleta. Faltando: {missing}. Use a opcao 'Forcar' para continuar.")

        processing_status['progress'] = 20

        # Step 3: Generate reversed list
        processing_status['current_step'] = 'reversing'
        processing_status['message'] = 'Gerando ordem inversa...'

        reversed_videos = list(reversed(videos))

        # Create temp file list
        filelist_path = BASE_DIR / ".filelist_temp.txt"
        with open(filelist_path, 'w') as f:
            for video in reversed_videos:
                f.write(f"file '{video['path']}'\n")

        processing_status['progress'] = 30

        # Step 4: Concatenate
        processing_status['current_step'] = 'concatenating'
        processing_status['message'] = 'Concatenando videos...'

        output_path = OUTPUT_DIR / output_name
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        # Remove existing output
        if output_path.exists():
            output_path.unlink()

        # Build ffmpeg command
        if reencode:
            cmd = [
                'ffmpeg', '-y', '-f', 'concat', '-safe', '0',
                '-i', str(filelist_path),
                '-c:v', 'libx264', '-preset', 'medium', '-crf', '23',
                '-c:a', 'aac', '-b:a', '192k',
                '-movflags', '+faststart',
                '-progress', 'pipe:1',
                str(output_path)
            ]
        else:
            cmd = [
                'ffmpeg', '-y', '-f', 'concat', '-safe', '0',
                '-i', str(filelist_path),
                '-c', 'copy',
                '-movflags', '+faststart',
                '-progress', 'pipe:1',
                str(output_path)
            ]

        # Calculate total duration
        total_duration = sum(v['duration'] for v in videos)

        # Run ffmpeg
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        # Monitor progress
        for line in process.stdout:
            if line.startswith('out_time_us='):
                try:
                    current_us = int(line.split('=')[1])
                    current_sec = current_us / 1000000
                    if total_duration > 0:
                        progress = min(95, 30 + int((current_sec / total_duration) * 65))
                        processing_status['progress'] = progress
                        processing_status['message'] = f'Concatenando... {progress - 30}%'
                except:
                    pass

        process.wait()

        # Cleanup temp file
        if filelist_path.exists():
            filelist_path.unlink()

        if process.returncode != 0:
            stderr = process.stderr.read()
            raise Exception(f"FFMPEG error: {stderr}")

        if not output_path.exists():
            raise Exception("Falha ao criar arquivo de saida")

        # Step 5: Get final stats
        processing_status['current_step'] = 'finishing'
        processing_status['message'] = 'Finalizando...'
        processing_status['progress'] = 98

        final_info = get_video_info(output_path)
        elapsed = time.time() - processing_status['start_time']

        processing_status['progress'] = 100
        processing_status['current_step'] = 'completed'
        processing_status['message'] = 'Concluido!'
        processing_status['result'] = {
            'success': True,
            'output_file': output_name,
            'output_path': str(output_path),
            'videos_processed': len(videos),
            'size': format_size(final_info['size']),
            'duration': format_duration(final_info['duration']),
            'elapsed': f"{elapsed:.1f}s",
            'reversed_order': [v['name'] for v in reversed_videos[:5]] + (['...'] if len(reversed_videos) > 5 else [])
        }

    except Exception as e:
        processing_status['error'] = str(e)
        processing_status['current_step'] = 'error'
        processing_status['message'] = f'Erro: {str(e)}'

    finally:
        processing_status['is_processing'] = False

# Routes

@app.route('/')
def index():
    """Main page"""
    return render_template('index.html')

@app.route('/api/videos', methods=['GET'])
def api_get_videos():
    """Get list of videos in input folder"""
    videos = scan_videos()
    missing, is_complete = detect_sequence_gaps(videos)

    total_size = sum(v['size'] for v in videos)
    total_duration = sum(v['duration'] for v in videos)

    return jsonify({
        'videos': videos,
        'count': len(videos),
        'total_size': format_size(total_size),
        'total_duration': format_duration(total_duration),
        'sequence_complete': is_complete,
        'missing_numbers': missing
    })

@app.route('/api/upload', methods=['POST'])
def api_upload():
    """Upload video files"""
    if 'files' not in request.files:
        return jsonify({'error': 'No files provided'}), 400

    files = request.files.getlist('files')
    uploaded = []
    errors = []

    INPUT_DIR.mkdir(parents=True, exist_ok=True)

    for file in files:
        if file.filename == '':
            continue

        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            filepath = INPUT_DIR / filename

            try:
                file.save(str(filepath))
                uploaded.append(filename)
            except Exception as e:
                errors.append({'file': filename, 'error': str(e)})
        else:
            errors.append({'file': file.filename, 'error': 'Formato nao suportado'})

    return jsonify({
        'uploaded': uploaded,
        'errors': errors,
        'count': len(uploaded)
    })

@app.route('/api/delete/<filename>', methods=['DELETE'])
def api_delete(filename):
    """Delete a video from input folder"""
    filepath = INPUT_DIR / secure_filename(filename)

    if filepath.exists():
        filepath.unlink()
        return jsonify({'success': True, 'message': f'{filename} removido'})

    return jsonify({'error': 'Arquivo nao encontrado'}), 404

@app.route('/api/clear', methods=['POST'])
def api_clear():
    """Clear all videos from input folder"""
    count = 0
    for ext in ALLOWED_EXTENSIONS:
        for f in INPUT_DIR.glob(f"*.{ext}"):
            f.unlink()
            count += 1
        for f in INPUT_DIR.glob(f"*.{ext.upper()}"):
            f.unlink()
            count += 1

    return jsonify({'success': True, 'deleted': count})

@app.route('/api/process', methods=['POST'])
def api_process():
    """Start video processing"""
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': 'Processamento ja em andamento'}), 400

    data = request.json or {}
    output_name = data.get('output_name', 'final.mp4')
    reencode = data.get('reencode', False)
    force = data.get('force', False)

    # Ensure .mp4 extension
    if not output_name.endswith('.mp4'):
        output_name += '.mp4'

    # Start processing thread
    thread = threading.Thread(
        target=process_videos_thread,
        args=(output_name, reencode, force)
    )
    thread.daemon = True
    thread.start()

    return jsonify({'success': True, 'message': 'Processamento iniciado'})

@app.route('/api/status', methods=['GET'])
def api_status():
    """Get processing status"""
    return jsonify(processing_status)

@app.route('/api/download/<filename>')
def api_download(filename):
    """Download processed video"""
    filepath = OUTPUT_DIR / secure_filename(filename)

    if filepath.exists():
        return send_file(
            str(filepath),
            as_attachment=True,
            download_name=filename
        )

    return jsonify({'error': 'Arquivo nao encontrado'}), 404

@app.route('/api/outputs', methods=['GET'])
def api_outputs():
    """List output files"""
    outputs = []

    if OUTPUT_DIR.exists():
        for ext in ALLOWED_EXTENSIONS:
            for f in OUTPUT_DIR.glob(f"*.{ext}"):
                info = get_video_info(f)
                outputs.append({
                    'name': f.name,
                    'size': format_size(info['size']),
                    'duration': format_duration(info['duration']),
                    'created': datetime.fromtimestamp(f.stat().st_mtime).strftime('%Y-%m-%d %H:%M')
                })

    return jsonify({'outputs': outputs})

@app.route('/api/delete-output/<filename>', methods=['DELETE'])
def api_delete_output(filename):
    """Delete output file"""
    filepath = OUTPUT_DIR / secure_filename(filename)

    if filepath.exists():
        filepath.unlink()
        return jsonify({'success': True})

    return jsonify({'error': 'Arquivo nao encontrado'}), 404

if __name__ == '__main__':
    # Ensure directories exist
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 50)
    print("Video Reverser - Web Interface")
    print("=" * 50)
    print(f"Input folder:  {INPUT_DIR}")
    print(f"Output folder: {OUTPUT_DIR}")
    print("=" * 50)
    print("Starting server on http://0.0.0.0:5000")
    print("=" * 50)

    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
