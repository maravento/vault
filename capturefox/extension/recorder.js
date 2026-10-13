export function recordingMime(Recorder = MediaRecorder) {
  return ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
    .find(type => Recorder.isTypeSupported(type)) || '';
}

export class CaptureSession extends EventTarget {
  constructor({ store, preview, canvas, mediaDevices = navigator.mediaDevices,
    Recorder = MediaRecorder, makeStream = tracks => new MediaStream(tracks),
    makeAudioContext = () => new AudioContext(), clock = () => performance.now() }) {
    super();
    Object.assign(this, { store, preview, canvas, mediaDevices, Recorder,
      makeStream, makeAudioContext, clock });
    this.state = 'idle';
    this.sources = [];
    this.accumulated = 0;
    this.gains = {};
  }
  emit(type, detail) { this.dispatchEvent(new CustomEvent(type, { detail })); }
  setState(state) { this.state = state; this.emit('state', state); }
  get elapsed() {
    return this.accumulated + (this.state === 'recording' ? this.clock() - this.segmentStarted : 0);
  }
  async start(options) {
    if (this.state !== 'idle') throw new Error('A recording is already in progress.');
    if (!['screen', 'camera', 'screen-camera'].includes(options.mode))
      throw new Error('Select a valid video source.');
    const system = ['system', 'both'].includes(options.audio);
    const mic = ['microphone', 'both'].includes(options.audio);
    if (system && !options.systemId)
      throw new Error('Enable CaptureFox_System_Audio and click Refresh devices.');
    if (system && mic && options.systemId === options.micId)
      throw new Error('Microphone and system audio must use different inputs.');
    this.sources = []; this.failure = null; this.cancelled = false;
    this.accumulated = 0; this.sequence = 0; this.pending = Promise.resolve();
    this.setState('starting');
    try {
      let screen, camera, microphone, internal;
      const video = { frameRate: { ideal: options.fps } };
      if (options.quality !== 'native') {
        video.height = { ideal: Number(options.quality), max: Number(options.quality) };
        video.width = { ideal: Math.round(Number(options.quality) * 16 / 9) };
      }
      if (options.mode.includes('screen')) {
        screen = await this.mediaDevices.getDisplayMedia({ video, audio: false });
        this.sources.push(screen);
        screen.getVideoTracks()[0].addEventListener('ended', () => {
          if (this.state === 'starting') this.cancelled = true;
          if (['recording', 'paused'].includes(this.state))
            this.stop().catch(error => this.emit('error', error));
        }, { once: true });
      }
      if (options.mode.includes('camera') || mic) {
        const constraints = {
          video: options.mode.includes('camera')
            ? { ...video, ...(options.cameraId ? { deviceId: { exact: options.cameraId } } : {}) }
            : false,
          audio: mic ? { ...(options.micId ? { deviceId: { exact: options.micId } } : {}),
            echoCancellation: true, noiseSuppression: true } : false
        };
        const stream = await this.mediaDevices.getUserMedia(constraints);
        this.sources.push(stream);
        camera = stream.getVideoTracks().length ? stream : null;
        microphone = stream.getAudioTracks().length ? stream : null;
      }
      if (system) {
        internal = await this.mediaDevices.getUserMedia({ video: false,
          audio: { deviceId: { exact: options.systemId }, echoCancellation: false,
            noiseSuppression: false, autoGainControl: false } });
        this.sources.push(internal);
      }
      if (this.cancelled) throw new Error('Screen capture was canceled.');
      let videoTrack;
      if (options.mode === 'screen-camera') {
        videoTrack = await this.compose(screen, camera, options);
      } else {
        videoTrack = (screen || camera).getVideoTracks()[0];
      }
      const audioTracks = [];
      if (microphone || internal) {
        this.audioContext = this.makeAudioContext();
        this.destination = this.audioContext.createMediaStreamDestination();
        for (const [name, stream, gain] of [['microphone', microphone, options.micGain],
          ['system', internal, options.systemGain]]) {
          if (!stream) continue;
          if (!stream.getAudioTracks().length) throw new Error('The selected input did not provide audio.');
          const source = this.audioContext.createMediaStreamSource(
            this.makeStream(stream.getAudioTracks()));
          const volume = this.audioContext.createGain();
          volume.gain.value = gain;
          source.connect(volume); volume.connect(this.destination);
          this.gains[name] = volume;
        }
        await this.audioContext.resume();
        audioTracks.push(...this.destination.stream.getAudioTracks());
      }
      this.output = this.makeStream([videoTrack, ...audioTracks]);
      const mimeType = recordingMime(this.Recorder);
      this.recorder = new this.Recorder(this.output, {
        ...(mimeType ? { mimeType } : {}), videoBitsPerSecond: options.fps === 60 ? 8000000 : 5000000
      });
      this.id = await this.store.create({ title: `Recording ${new Date().toLocaleString('en-US')}`,
        mode: options.mode, audio: options.audio, mimeType: this.recorder.mimeType || mimeType });
      this.done = new Promise((resolve, reject) => { this.resolve = resolve; this.reject = reject; });
      this.recorder.addEventListener('dataavailable', event => {
        if (!event.data?.size || this.failure) return;
        const sequence = this.sequence++;
        this.pending = this.pending.then(() => this.store.append(this.id, sequence, event.data))
          .catch(error => {
            this.failure = error;
            this.emit('error', new Error('A recording chunk could not be saved. Recording was stopped.'));
            if (this.recorder.state !== 'inactive') this.stop().catch(() => {});
          });
      });
      this.recorder.addEventListener('error', event => {
        this.failure ||= event.error || new Error('The video recorder failed.');
        this.emit('error', this.failure);
        if (this.recorder.state !== 'inactive') this.stop().catch(() => {});
      });
      this.recorder.addEventListener('stop', () => this.finalize(), { once: true });
      this.recorder.start(2000);
      this.segmentStarted = this.clock();
      this.setState('recording');
      this.preview.srcObject = this.output;
      await this.preview.play().catch(() => {});
      return this.id;
    } catch (error) {
      if (this.id && this.recorder?.state === 'inactive')
        await this.store.finish(this.id, { status: 'failed', durationMs: 0 }).catch(() => {});
      await this.cleanup();
      this.setState('idle');
      throw error;
    }
  }
  async compose(screen, camera, options) {
    const createVideo = async stream => {
      const video = document.createElement('video');
      video.muted = true; video.playsInline = true; video.srcObject = stream;
      await video.play(); return video;
    };
    const screenVideo = await createVideo(screen);
    const cameraVideo = await createVideo(camera);
    this.compositionVideos = [screenVideo, cameraVideo];
    const settings = screen.getVideoTracks()[0].getSettings();
    const originalWidth = screenVideo.videoWidth || settings.width || 1920;
    const originalHeight = screenVideo.videoHeight || settings.height || 1080;
    const scale = options.quality === 'native' ? 1 : Math.min(1, Number(options.quality) / originalHeight);
    this.canvas.width = Math.max(2, Math.floor(originalWidth * scale / 2) * 2);
    this.canvas.height = Math.max(2, Math.floor(originalHeight * scale / 2) * 2);
    const context = this.canvas.getContext('2d', { alpha: false });
    const draw = () => {
      const width = this.canvas.width, height = this.canvas.height;
      context.drawImage(screenVideo, 0, 0, width, height);
      const ratio = { small: 0.16, medium: 0.22, large: 0.3 }[options.cameraSize] || 0.22;
      const boxWidth = width * ratio;
      const boxHeight = options.cameraShape === 'circle' ? boxWidth : boxWidth * 9 / 16;
      const padding = Math.min(width, height) * 0.025;
      const x = options.cameraPosition.endsWith('right') ? width - boxWidth - padding : padding;
      const y = options.cameraPosition.startsWith('bottom') ? height - boxHeight - padding : padding;
      context.save();
      if (options.cameraShape === 'circle') {
        context.beginPath(); context.arc(x + boxWidth / 2, y + boxHeight / 2,
          boxWidth / 2, 0, Math.PI * 2); context.clip();
      }
      const sourceWidth = cameraVideo.videoWidth || 1280;
      const sourceHeight = cameraVideo.videoHeight || 720;
      const fit = Math.max(boxWidth / sourceWidth, boxHeight / sourceHeight);
      const croppedWidth = boxWidth / fit, croppedHeight = boxHeight / fit;
      context.drawImage(cameraVideo, (sourceWidth - croppedWidth) / 2,
        (sourceHeight - croppedHeight) / 2, croppedWidth, croppedHeight,
        x, y, boxWidth, boxHeight);
      context.restore();
    };
    draw(); this.drawTimer = setInterval(draw, 1000 / options.fps);
    this.composed = this.canvas.captureStream(options.fps);
    return this.composed.getVideoTracks()[0];
  }
  setGain(name, value) {
    if (this.gains[name]) this.gains[name].gain.value = Math.max(0, Math.min(2, value));
  }
  pause() {
    if (this.state !== 'recording') return;
    this.recorder.pause();
    this.accumulated += this.clock() - this.segmentStarted;
    this.setState('paused');
  }
  resume() {
    if (this.state !== 'paused') return;
    this.recorder.resume(); this.segmentStarted = this.clock(); this.setState('recording');
  }
  stop() {
    if (this.state === 'stopping') return this.done;
    if (!['recording', 'paused'].includes(this.state)) return Promise.resolve();
    this.accumulated = this.elapsed;
    this.setState('stopping');
    this.recorder.stop();
    return this.done;
  }
  async finalize() {
    try {
      await this.pending;
      await this.store.finish(this.id, { status: this.failure ? 'failed' : 'complete',
        durationMs: this.accumulated });
      const record = await this.store.get(this.id);
      await this.cleanup(); this.setState('idle');
      this.emit('finished', record);
      this.resolve(record);
    } catch (error) {
      await this.cleanup(); this.setState('idle'); this.emit('error', error); this.reject(error);
    }
  }
  async cleanup() {
    clearInterval(this.drawTimer); this.drawTimer = null;
    const tracks = new Set([...this.sources, this.output, this.composed]
      .filter(Boolean).flatMap(stream => stream.getTracks()));
    for (const track of tracks) track.stop();
    for (const video of this.compositionVideos || []) { video.pause(); video.srcObject = null; }
    this.compositionVideos = []; this.sources = []; this.output = null; this.composed = null;
    this.preview.srcObject = null;
    if (this.audioContext) await this.audioContext.close().catch(() => {});
    this.audioContext = null; this.gains = {}; this.id = null;
  }
}
