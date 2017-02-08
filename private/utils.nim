import os
import strutils
import sequtils
import sets
import logging
import tables
import osproc
import httpclient
import uri
import json
import base64
import winutils


proc readTincConf(tincConf: string): Table[string,string] =
  var confTable = initTable[string,string]()
  for line in lines(tincConf):
    var cfgParts: seq[string]
    if line.contains("="):
      cfgParts = line.split("=")
      confTable[cfgParts[0].strip()] = cfgParts[1].strip()
  return confTable


proc writeTincConf(tincConf: string, tincData: Table[string,string]) =
  var buffer = ""
  for key, value in tincData.pairs():
      buffer &= key & " = " & value & "\n"
  writeFile(tincConf,buffer)


proc getAddressesInUse*(networkPath: string): seq[string] =
  var addresses = newSeq[string]()
  for file in walkDir(joinPath(networkPath,"hosts")):
     if file.kind == pcFile:
        for line in lines(file.path):
          if line.startsWith("Subnet"):
            var cfgParts = line.split("=")
            addresses.add(cfgParts[1].strip())
  return addresses


proc listNetworks*(tincConf: string): seq[string] =
  var networks = newSeq[string]()
  for x in walkDir(tincConf):
    if x.kind == pcDir:
      var files: seq[string]
      files = x.path.split(DirSep)
      networks.add(files[files.high])
  networks = filterIt(networks, it != "doc" and it != "tap-win32" and it != "tap-win64")
  return networks


proc getPortInUse*(networkPath: string): int =
  var
    port = -1
    tincData = readTincConf(joinPath(networkPath,"tinc.conf"))
  if "Port" in tincData:
    port = parseInt(tincData["Port"])
  if port == -1:
    port = 655
  return port


proc getTapDevice*(tincConf: string, networkPath: string): int =
  var
    tapDevice = -1
    tincData = readTincConf(joinPath(tincConf,networkPath,"tinc.conf"))
  if "Device" in tincData:
    tapDevice = parseInt(tincData["Device"])
  return tapDevice


proc getUnusedTapDevice(tincConf: string): int =
  let networks = listNetworks(tincConf)
  var
    used = newSeq[int]()
    tapDevice = 0
  for network in networks:
    used.add(getTapDevice(tincConf,network))
  tapDevice = used.max + 1
  return tapDevice


proc getNetworkPaths*(tincConf: string): seq[string] =
  var networkPaths = newSeq[string]()
  for network in listNetworks(tincConf):
    networkPaths.add(joinPath(tincConf,network))
  return networkPaths


proc getNetworkPortMap*(tincConf: string): Table[string,int] =
  var portMap = initTable[string,int]()
  for network in listNetworks(tincConf):
    portMap[network] = getPortInUse(joinPath(tincConf,network))
  return portMap


proc getAllAddressesInUse*(tincConf: string): seq[string] =
  var addresses = newSeq[string]()
  for network in getNetworkPaths(tincConf):
    addresses = concat(addresses,getAddressesInUse(network))
  return addresses


proc findUnusedSubnet*(tincConf: string): string =
  var addresses = getAllAddressesInUse(tincConf)
  if addresses.len == 0:
    return "10.0.0.1"
  var uniqueAddresses = initSet[int]()
  for address in addresses:
    uniqueAddresses.incl parseInt(address.split(".")[2])
  for i in 0..254:
    if not (i in uniqueAddresses):
      return "10.0.$#.1".format($i)


# proc getUnusedIP(networkPath: string): string =
#   var inuse = getAddressesInUse(networkPath)
#   if inuse.len == 0 or inuse.len == 254:
#     fatal(networkPath & " probably doesn't have any IPs listed or is at max")
#     quit(QuitFailure)
#   var
#     subnet = inuse[0].split(".")[2]
#     lastDigitsInUse = newSeq[int]()
#   for ip in inuse:
#     lastDigitsInUse.add(parseInt(ip.split(".")[3]))
#   for i in 2..254:
#     if not i in lastDigitsInUse:
#       return "10.0.$#.$#".format([subnet,$i])


proc getUnusedPort*(tincConf: string): int =
  var ports = toSeq(getNetworkPortMap(tincConf).values())
  for port in 655..9999:
    if port notin ports:
      return port


proc createNetwork*(network: string, ip: string, port: int, hostname: string,
                   tincConf: string, tincExe: string, connectTo: string = "", pubip: string = "") =
  #make network folder
  createDir(joinPath(tincConf,network))
  createDir(joinPath(tincConf,network,"hosts"))
  createDir(joinPath(tincConf,network,"pending"))
  #make tinc.conf
  var tincConfString =  "Name = $#\nPort = $#\n".format([hostname, $port])
  if connectTo != "":
    tincConfString &= "ConnectTo = $#".format([connectTo])
  writeFile(joinPath(tincConf,network,"tinc.conf"),tincConfString)
  #generate key
  echo execProcess("$# -n $# -K4096".format([tincExe,network]))
  #if routing mode add subnet to public key
  #add port to publickey file
  var publicKey = toSeq(lines(joinPath(tincConf,network,"hosts",hostname)))
  if not pubip.isNilOrEmpty():
    publicKey.insert("Address = $#".format(pubip),0)
  publicKey.insert("Port = $#".format(port),0)
  publicKey.insert("Subnet = $#/32".format(ip),0)
  writeFile(joinPath(tincConf,network,"hosts",hostname), publicKey.join("\n"))
  if system.hostOS != "windows":
    let
      tincUpConf = "ifconfig $INTERFACE " & ip & " netmask 255.255.255.0"
      tincDownConf = """ifconfig $INTERFACE down"""
      tincUpPath= joinPath(tincConf,network,"tinc-up")
      tincDownPath = joinPath(tincConf,network,"tinc-down")
    writeFile(tincUpPath,tincUpConf)
    writeFile(tincDownPath,tincDownConf)
    os.setFilePermissions(tincUpPath,{fpUserExec,fpOthersExec})
    os.setFilePermissions(tincDownPath,{fpUserExec,fpOthersExec})
    if system.hostOS == "macosx":
      var macTincFile = open(joinPath(tincConf,network,"tinc.conf"),FileMode.fmAppend)
      macTincFile.write("\nDevice = /dev/tap$#".format(getUnusedTapDevice(tincConf)))
      macTincFile.close()
  else:
    echo "Setting up adapter"
    echo setupAdapter(network,tincConf)
    echo "Setting static ip"
    echo execProcess("""netsh interface ip set address "$#" static $# 255.255.255.0""".format([network,ip]))
    var winTincFile = open(joinPath(tincConf,network,"tinc.conf"),FileMode.fmAppend)
    winTincFile.write("\nInterface = $#".format(network))
    winTincFile.close()
  echo "Your IP: " & $ip


proc getGatewayNetwork*(gateway: string, network: string): JsonNode =
  var
    address = gateway & "/networks/" & network & "/join"
    results = parseJson(getContent(address))
  if not results.hasKey("error"):
    return results

proc getPublicKey(network: string, tincConf: string): string =
  let
    tincConfFile = readTincConf(joinPath(tincConf,network,"tinc.conf"))
    name = tincConfFile["Name"]
  return readFile(joinPath(tincConf,network,"hosts",name))

proc joinNetwork*(gateway: string, network: string, port: int, hostname: string,
                   tincConf: string, tincExe: string) =
  let
    address = "$#/networks/$#/join".format([gateway,network])
    networkInfo = getGatewayNetwork(gateway,network)
    ip = networkInfo["ip"].getStr()
    connectTo = networkInfo["host_name"].getStr()
    remotePubkey = decode(networkInfo["pubkey"].getStr())
  createNetwork(network,ip,port,hostname,tincConf,tincExe,connectTo = connectTo)
  writeFile(joinPath(tincConf,network,"hosts",connectTo),remotePubkey)
  var data = newMultipartData()
  data["name"] = hostname
  data["pubkey"] = encode(getPublicKey(network, tincConf))
  var joinResponse = parseJson("{}")
  try:
    var jsonResp = postContent(address,multipart=data)
    #debug jsonResp
    joinResponse = parseJson(jsonResp)
  except:
    raise
  if joinResponse.hasKey("error"):
    echo joinResponse["error"]
    removeDir(joinPath(tincConf,network))
  else:
    echo "Successfully joined " & network
