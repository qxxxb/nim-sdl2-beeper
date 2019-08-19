import
  unittest,
  os,
  times,
  logging,
  sdl2,
  ./beeper

suite "Beeper":

  test "simple":
    addHandler(newConsoleLogger())

    if sdl2.init(INIT_AUDIO) != SdlSuccess:
      raise AudioError.newException "Couldn't initialize SDL2 audio"

    beeper.open()
    beeper.setVolume(1.0)
    beeper.play()

    const c4 = 261.63
    const e4 = 329.63
    const g4 = 392.00

    beeper.setFrequency(c4)
    sleep(500)
    beeper.setFrequency(e4)
    sleep(500)
    beeper.setFrequency(g4)
    sleep(500)

    beeper.stop()
    beeper.close()
    sdl2.quit()
