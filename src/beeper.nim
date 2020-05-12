import
  sdl2,
  sdl2/audio,
  math,
  logging,
  times,
  options,
  locks

type AudioError* = object of ValueError

template throw(msg: string) =
  raise AudioError.newException(msg)

# ---
# Obtained audio settings
var obtainedSpec: AudioSpec

# ---

type ModulationDurations* = object
  ## Play the sound on and off repeatedly
  on*: Duration
  off*: Duration

type ModulationState = object
  lastTime: Time ## Most recent time of transition from on to off or vice versa
  on: bool ## Whether sound is currently playing or not

type Modulation = object
  durations: ModulationDurations
  state: ModulationState

type State = object
  deviceId: AudioDeviceID
  freq: float ## Units: Hz
  volume: float ## Range: [0 .. 1]
  pos: int ## Current playback position, units: samples
  modulation: Option[Modulation]

var state: State

# We need this lock to prevent users from changing state (e.g. `setModulation`)
# while the audio callback is running
var stateLock: Lock
initLock(stateLock)

# ---
# Calculate the offset in bytes from the start of the audio stream to the
# memory address at `sample` and `channel`.
#
# Channels are interleaved.

proc calculateOffset_s16(sample, channel: int): int =
  (sample * int16.sizeof() * obtainedSpec.channels.int()) +
  (channel * int16.sizeof())

proc calculateOffset_f32(sample, channel: int): int =
  (sample * float32.sizeof() * obtainedSpec.channels.int()) +
  (channel * float32.sizeof())

# ---
# Convert a normalized data value (range: 0.0 .. 1.0) to a data value matching
# the audio format.

proc writeData_s16(
  ptrData: ptr float,
  data: float
) =
  var ptrTyped = cast[ptr int16](ptrData)
  let dataScaled = data * int16.high().toFloat()
  ptrTyped[] = dataScaled.int16()

proc writeData_f32(
  ptrData: ptr float,
  data: float
) =
  let ptrTyped = cast[ptr float32](ptrData)
  ptrTyped[] = data.float32()

# ---
# Generate audio data. This is how the waveform is generated.

proc getSineData(): float =
  ## Generate a sine wave

  let sampleRate = obtainedSpec.freq.toFloat()

  # Units: samples
  let period = sampleRate / state.freq

  # Reset ``state.pos`` when it reaches the start of a period so it doesn't run
  # off to infinity (though this won't happen unless you are playing sound for
  # a very long time)
  if state.pos mod period.toInt() == 0:
    state.pos = 0

  let pos = state.pos.toFloat()
  let angular_freq = (1 / period) * 2 * PI
  let amplitude = state.volume

  sin(pos * angular_freq) * amplitude

proc getData(): float =
  ## Generate a modulated sine wave

  if state.modulation.isNone():
    getSineData()
  else:
    template modulation: untyped = state.modulation.get()

    let now = times.getTime()
    let elapsed = now - modulation.state.lastTime

    case modulation.state.on
    of true:
      if elapsed > modulation.durations.on:
        modulation.state.lastTime = now
        modulation.state.on = false
        0.0
      else:
        getSineData()
    of false:
      if elapsed > modulation.durations.off:
        modulation.state.lastTime = now
        modulation.state.on = true
        getSineData()
      else:
        0

var calculateOffset: proc (sample, channel: int): int
var writeData: proc (ptrData: ptr float, data: float)

proc audioCallback(
  userdata: pointer,
  stream: ptr uint8,
  len: cint
) {.cdecl.} =
  setupForeignThreadGc()

  # Write data to the entire buffer by iterating through all samples and
  # channels.
  for sample in 0 ..< obtainedSpec.samples.int():
    acquire(stateLock)
    let data = getData()
    state.pos.inc()
    release(stateLock)

    # Write the same data to all channels
    for channel in 0 ..< obtainedSpec.channels.int():
      let offset = calculateOffset(sample, channel)
      var ptrData = cast[ptr float](cast[ByteAddress](stream) +% offset)
      writeData(ptrData, data)

# ---

proc open*() =
  var desired = AudioSpec(
    freq: 44100.cint(),
    format: AUDIO_S16,
    channels: 1,
    samples: 512,
    callback: audioCallback
  )

  state.deviceId = openAudioDevice(
    device = nil, # Name of device, which we don't care about
    iscapture = 0, # We are not recording audio
    desired = desired.addr(),
    obtained = obtainedSpec.addr(),
    allowed_changes = 0 # Allow any changes between desired and obtained
  )

  if state.deviceId == 0:
    throw "Couldn't open audio device" & $getError()

  case obtainedSpec.format
  of AUDIO_S16:
    calculateOffset = calculateOffset_s16
    writeData = writeData_s16
  of AUDIO_F32:
    calculateOffset = calculateOffset_f32
    writeData = writeData_f32
  else:
    throw "Unsupported audio format: " & $obtainedSpec.format

  debug "[beeper][init] frequency: ", obtainedSpec.freq
  debug "[beeper][init] format: ", obtainedSpec.format
  debug "[beeper][init] channels: ", obtainedSpec.channels
  debug "[beeper][init] samples: ", obtainedSpec.samples
  debug "[beeper][init] padding: ", obtainedSpec.padding
  debug "[beeper][init] size: ", obtainedSpec.size

proc close*() = closeAudioDevice(state.deviceId)

proc play*() = pauseAudioDevice(state.deviceId, 0)
proc stop*() = pauseAudioDevice(state.deviceId, 1)

proc setFrequency*(frequency: float) =
  state.freq = frequency

proc setVolume*(volume: float) =
  assert (volume >= 0.0) and (volume <= 1.0)
  state.volume = volume

proc setModulationDurations*(modulationDurations: ModulationDurations) =
  template md: untyped = modulationDurations

  if state.modulation.isSome():
    state.modulation.get().durations = md
  else:
    state.modulation = Modulation(
      durations: md,
      state: ModulationState()
    ).some()

proc disableModulation*() =
  state.modulation = Modulation.none()
