import
  sdl2,
  sdl2/audio,
  math,
  logging

type AudioError* = object of Exception

template throw(msg: string) =
  raise AudioError.newException(msg)

# Requested audio settings.

type RequestedSpec = object
  freq: int ## Sample rate, units: Hz
  format: AudioFormat ## E.g. ``AUDIO_S16``, ``AUDIO_F32``
  samples: uint16 ## Buffer size in samples
  channels: uint8
  padding: uint16
  callback: AudioCallback

# ---

# Obtained audio settings
var obtainedSpec: AudioSpec

# ---

type State = object
  freq: int ## Units: Hz
  volume: float ## Range: [0 .. 1]
  sample: int ## Current playback position, units: samples

var state: State

# ---

proc sine_s16(): int16 =
  ## Generate sine wave

  let sampleRate = obtainedSpec.freq.tofloat()

  # Units: samples
  let period = sampleRate / state.freq.toFloat()

  let x = (state.sample mod period.int()).toFloat()
  let angular_freq = (1 / period) * 2 * PI
  let amplitude = (int16.high().toFloat() * state.volume)

  round(sin(x * angular_freq) * amplitude).int16()

proc sine_f32(): float32 =
  ## Generate sine wave

  let sampleRate = obtainedSpec.freq.tofloat()

  # Units: samples
  let period = sampleRate / state.freq.toFloat()

  let x = (state.sample mod period.int()).toFloat()
  let angular_freq = (1 / period) * 2 * PI
  let amplitude = state.volume

  sin(x * angular_freq) * amplitude

# ---

# The sample size is the size specified in format multiplied by the number of
# channels. That means each sample contains data for each sample. Channel data
# is interleaved.

proc writeCallback_s16(
  userdata: pointer,
  stream: ptr uint8,
  len: cint
) {.cdecl.} =
  for sample in 0 ..< obtainedSpec.samples.int():
    let data = sine_s16()

    for channel in 0 ..< obtainedSpec.channels.int():
      let offset =
        (sample * int16.sizeof() * obtainedSpec.channels.int()) +
        (channel * int16.sizeof())

      var ptrData = cast[ptr int16](
        cast[ByteAddress](stream) + offset
      )

      ptrData[] = data

    state.sample.inc()

proc writeCallback_f32(
  userdata: pointer,
  stream: ptr uint8,
  len: cint
) {.cdecl.} =
  for sample in 0 ..< obtainedSpec.samples.int():
    let data = sine_f32()

    for channel in 0 ..< obtainedSpec.channels.int():
      let offset =
        (sample * float32.sizeof() * obtainedSpec.channels.int()) +
        (channel * float32.sizeof())

      var ptrData = cast[ptr float32](
        cast[ByteAddress](stream) + offset
      )

      ptrData[] = data

    state.sample.inc()

# ---

const requestedSpec = RequestedSpec(
  freq: 44100,
  format: AUDIO_S16,
  samples: 4096,
  channels: 1,
  padding: 0,
  callback: writeCallback_s16
)

# ---

proc init*() =
  # Init audio playback
  if init(INIT_AUDIO) != SdlSuccess:
    throw "Couldn't initialize SDL"

  var requested = AudioSpec(
    freq: requestedSpec.freq.cint(),
    format: requestedSpec.format,
    channels: requestedSpec.channels,
    samples: requestedSpec.samples,
    padding: requestedSpec.padding,
    callback: requestedSpec.callback
  )

  if openAudio(requested.addr(), obtainedSpec.addr()) != 0:
    throw "Couldn't open audio device" & $getError()

  debug("[beeper][init] frequency: ", obtainedSpec.freq)
  debug("[beeper][init] format: ", obtainedSpec.format)
  debug("[beeper][init] channels: ", obtainedSpec.channels)
  debug("[beeper][init] samples: ", obtainedSpec.samples)
  debug("[beeper][init] padding: ", obtainedSpec.padding)
  debug("[beeper][init] size: ", obtainedSpec.size)

  case obtainedSpec.format
  of AUDIO_S16: obtainedSpec.callback = writeCallback_s16
  of AUDIO_F32: obtainedSpec.callback = writeCallback_f32
  else:
    throw "Unsupported audio format: " & $obtainedSpec.format

proc quit*() = sdl2.quit()

proc play*() = pauseAudio(0)
proc stop*() = pauseAudio(1)

proc setFrequency*(frequency: int) =
  state.freq = frequency

proc setVolume*(volume: float) =
  assert (volume >= 0.0) and (volume <= 1.0)
  state.volume = volume
