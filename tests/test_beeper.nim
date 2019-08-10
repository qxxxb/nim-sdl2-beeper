import
  unittest,
  os,
  times,
  logging,
  ./beeper

suite "Beeper":
  addHandler(newConsoleLogger())
  beeper.init()

  test "simple":
    setFrequency(440)
    setVolume(0.5)

    block:
      let start = getTime()
      play()
      sleep(2000)
      stop()
      info("[simple]: duration: ", getTime() - start)

    sleep(1000)
    setFrequency(600)
    setVolume(0.75)

    block:
      let start = getTime()
      play()
      sleep(1000)
      stop()
      info("[simple]: duration: ", getTime() - start)

  beeper.quit()
