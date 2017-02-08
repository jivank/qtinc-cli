import strutils
import sequtils
import sets
import hashes
import os
import osproc
import logging

type VPNAdapter* = ref object of RootObj
  name*: string
  disconnected*: bool

proc hash(x: VPNAdapter): Hash =
  ## Computes a Hash from `x`.
  var h: Hash = 0
  h = h !& hash(x.name)
  h = h !& hash(x.disconnected)
  result = !$h

proc getAdapters(): HashSet[string] =
  var
    vpns = initSet[string]()
    onAdapter = false
    temp = VPNAdapter()
    ipconfig = execProcess("ipconfig /all")
  for y in ipconfig.split("\n"):
    if y.startsWith("Ethernet adapter"):
      temp.name = y.split("Ethernet adapter").join("").strip(chars={' ',':'})
      onAdapter = true
      continue
    if y[0].isAlpha():
       onAdapter = false
    if onAdapter:
      if y.strip().startsWith("Media"):
        if y.strip().endsWith("disconnected"):
          temp.disconnected = true
      if y.strip().startsWith("Description"):
        if y.strip().contains("TAP-Win32 Adapter V9"):
          vpns.incl temp.name
          temp = VPNAdapter()
          onAdapter = false
  return vpns

proc setupAdapter*(network: string, tincConf: string): bool =
  var
    initialState = getAdapters()
    tapPath: string
  if hostCPU == "amd64":
    tapPath = "tap-win64"
  else:
    tapPath = "tap-win32"
  let
    finalTapPath = joinPath(tincConf,tapPath)
    tapInstall = joinPath(finalTapPath,"tapinstall.exe").quoteShellWindows
    oemwin2k = joinPath(finalTapPath,"OemWin2k.inf").quoteShellWindows
    installCmd = "$# install $# tap0901".format([tapInstall,oemwin2k])
  echo execProcess(installCmd)
  var
    finalState = getAdapters()
    results = finalState - initialState
    retryCounter = 0
  echo "Waiting for adapter.."
  while results.len == 0 and retryCounter < 15:
    finalState = getAdapters()
    results = finalState - initialState
    retryCounter.inc()
    sleep 3000

  if results.len != 1:
    echo("Error: new adapter not found..")
    return false
  var
    result = toSeq(results.items())[0]
    renameAdapterCmd = """netsh interface set interface name="$#" newname="$#" """.format([result,network])
  echo execProcess(renameAdapterCmd)
  return true
