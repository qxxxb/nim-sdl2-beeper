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
  samples: uint16 ## Buffer size in samples
  channels: uint8
  padding: uint16

const requestedSpec = RequestedSpec(
  freq: 44100,
  samples: 4096,
  channels: 1,
  padding: 0
)

# Expected audio settings. If these are not supported an error will be thrown
# in `init`

type ExpectedSpec = object
  format: AudioFormat
  bitDepth: int

const expectedSpec = ExpectedSpec(
  format: AUDIO_S16,
  bitDepth: 16
)

proc check(obtained: AudioSpec) =
  if obtained.format != expectedSpec.format:
    throw("Couldn't open 16 bit audio channel")

proc bytesPerSample(): int =
  const bitsInByte = 8
  expectedSpec.bitDepth div bitsInByte

# ---

# Obtained audio settings
var obtainedSpec: AudioSpec

# ---

type State = object
  freq: int ## Units: Hz
  volume: float ## Range: [0 .. 1]
  pos: int ## Current playback position

var state: State

proc sine(): int16 =
  ## Generate sine wave

  let sampleRate = obtainedSpec.freq.tofloat()

  # Units: samples
  let period = sampleRate / state.freq.toFloat()

  let pos = (state.pos mod period.int()).toFloat()
  let angular_freq = (1 / period) * 2 * PI
  let amplitude = (int16.high().toFloat() * state.volume)

  round(sin(pos * angular_freq) * amplitude).int16()

proc writeCallback(
  userdata: pointer,
  stream: ptr uint8,
  len: cint
) {.cdecl.} =
  for i in 0 ..< int16(obtainedSpec.samples):
    var ptrSample = cast[ptr int16](
      cast[ByteAddress](stream) + i * bytesPerSample()
    )

    ptrSample[] = sine()

    state.pos.inc()

proc init*() =
  # Init audio playback
  if init(INIT_AUDIO) != SdlSuccess:
    throw("Couldn't initialize SDL")

  var requested = AudioSpec(
    freq: requestedSpec.freq.cint(),
    format: expectedSpec.format,
    channels: requestedSpec.channels,
    samples: requestedSpec.samples,
    padding: requestedSpec.padding,
    callback: writeCallback
  )

  if openAudio(requested.addr(), obtainedSpec.addr()) != 0:
    throw("Couldn't open audio device" & $getError())

  debug("[beeper][init] frequency: ", obtainedSpec.freq)
  debug("[beeper][init] format: ", obtainedSpec.format)
  debug("[beeper][init] channels: ", obtainedSpec.channels)
  debug("[beeper][init] samples: ", obtainedSpec.samples)
  debug("[beeper][init] padding: ", obtainedSpec.padding)

  obtainedSpec.check()

proc quit*() = sdl2.quit()

proc play*() = pauseAudio(0)
proc stop*() = pauseAudio(1)

proc setFrequency*(frequency: int) =
  state.freq = frequency

proc setVolume*(volume: float) =
  assert (volume >= 0.0) and (volume <= 1.0)
  state.volume = volume
