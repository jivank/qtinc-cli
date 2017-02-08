import os, logging, docopt, random, tables, osproc, strutils
import private/utils
import private/validation
import httpclient
import json
import re
let doc = """
qtinc.

Usage:
  qtinc create <network> [--port=<port>] [--private-ip=<ip>] [--public-ip=<ip>] [--debug]
  qtinc join <gateway> <network> [<alternative_hostname>] [--port=<port>] [--debug]
  qtinc list <gateway>
  qtinc (-h | --help)
  qtinc --version

Options:
  <network>           Name of network to join or create.
  <gateway>           URL of qtinc gateway to connect to. (e.g. http://example.com:5000)
  --port=<port>       Local port tinc will use for this net.
  --private-ip=<ip>   Private IP you would like to start with. (e.g. 10.0.0.1)
  --public-ip=<ip>    Public IP others will connect from.
  --debug             Enable debug messages.

  -h --help           Show this screen.
  --version           Show version.
"""



let args = docopt(doc, version = "qtinc 0.1")
var L = newConsoleLogger()
addHandler(L)
proc debugOut(s: varargs[string]) = 
  if args["--debug"]:
    debug(s)
debugOut($args)
var hostname = re.replace(execProcess("hostname").string,re"[^A-Za-z0-9]+")
debugOut("Hostname`: ", hostname)

var tincConf: string
var tincExe: string


#find path for config
if system.hostOS == "linux":
  tincConf = "/etc/tinc"
if system.hostOS == "macosx":
  let
    osxDir1 = "/usr/local/etc/tinc"
    osxDir2 = "/opt/local/etc/tinc"
  if existsDir(osxDir1):
    tincConf = osxDir1
  if existsDir(osxDir2):
    tincConf = osxDir2
  if existsDir(osxDir1) and existsDir(osxDir2):
    info(osxDir1  & " and "  & osxDir2  & " both exist, going with latter")
if system.hostOS == "windows":
  let
    winDir1 = r"C:\Program Files (x86)\tinc"
    winDir2 = r"C:\Program Files\tinc"
  if existsDir(winDir1):
    tincConf = winDir1
  if existsDir(winDir2):
      tincConf = winDir2
  if existsDir(winDir1) and existsDir(winDir2):
    debugOut(winDir1  & " and "  & winDir2  & " both exist, going with latter")

debugOut("tincConf: " & tincConf)
if not existsDir(tincConf):
  fatal("Configuration does not exist: " & tincConf)
  quit(QuitFailure)

if system.hostOS == "linux" or system.hostOS == "macosx":
  tincExe = findExe("tincd")
if system.hostOS == "windows":
  tincExe = joinPath(tincConf,"tincd.exe")

debugOut("tincExe: " & tincExe)

proc listNetworks(gateway: string) =
  let address = gateway & "/networks"
  for network in getContent(address).parseJson():
    echo strip($network, chars = {'\"'})

if args["list"]:
  listNetworks($args["<gateway>"])
elif args["create"]:
  var
    network = $args["<network>"]
    ip = ""
  if args["--private-ip"].kind != vkNone:
     ip = $args["--private-ip"]
  var port = 0
  if args["--port"].kind != vkNone:
     port = parseInt($args["--port"])
  checkNetwork(network,tincConf)
  checkIp(network,ip,tincConf)
  checkPort(network,port,tincConf)
  createNetwork(network,ip,port,hostname,tincConf,tincExe)
elif args["join"]:
  var
    network = $args["<network>"]
    port = -1
    gateway = $args["<gateway>"]
  if $args["--port"] == "":
    port = parseInt($args["--port"])
  if port == -1:
    port = getUnusedPort(tincConf)
  if args["<alternative_hostname>"].kind != vkNone:
    hostname = $args["<alternative_hostname>"]
  checkNetwork(network,tincConf)
  checkPort(network,port,tincConf)
  joinNetwork(gateway,network,port,hostname,tincConf,tincExe)
  if system.hostOS == "windows":
    echo execProcess("$# -n $#".format([tincExe,network]))
