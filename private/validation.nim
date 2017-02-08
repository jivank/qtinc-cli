import os
import logging
import utils
import strutils
import tables


proc checkNetwork*(network: string, confPath: string) =
  if dirExists(joinPath(confPath,network)):
    fatal("Network: "& network & " already exists!")
    quit(QuitFailure)

proc checkIp*(network: string, ip: var string, confPath: string) =
  if ip == "":
    ip = findUnusedSubnet(confPath)
  else:
    if ip in getAllAddressesInUse(network):
      fatal("Unable to use " & $ip)
      quit(QuitFailure)
    var ipParts = ip.split(".")
    if ipParts[ipParts.high] != "1":
      fatal("Please use IP ending in .1")
      quit(QuitFailure)

proc checkPort*(network: string, port: var int, confPath: string) =
  if port != 0:
    for netw, usedPort in getNetworkPortMap(confPath).pairs():
      if port == usedPort:
        fatal("Port " & $port & " already in use. In conflict with network: " & $netw)
        quit(QuitFailure)
  else:
    port = getUnusedPort(confPath)
