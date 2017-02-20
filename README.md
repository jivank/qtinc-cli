# qtinc-cli
This is experimental software, please use at your own risk.

This was a quick personal project to learn Nim and automate setting up tinc networks. Please let me know if you have any suggestions and I am always open to pull requests.

Tested Platforms:
- Windows
- MacOS
- Linux

# Implementation

I take a fairly simple approach. Each network is has its own /24 subnet such as 10.0.0.0. With the current implementation you may only have 254 hosts per network and currently only 254 networks. The qtinc server will give new clients an unused IP address based off current IPs found in the pending and hosts folder.

# Setup
Requirements:
- Nim
- Nimble
- Docopt

After installing Nim and Nimble, you may install Docopt with the following command:
`nimble install docopt`

Now compile the binary with:
`nim c qtinc`


# Usage
```
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
  ```

# Examples

Join a network

`./qtinc join http://example.com:5000 testnetwork`

Create a network

`./qtinc create testnetwork `

# Notes

Windows will automatically start the tinc process. You will have the manually start the tinc process for Linux and MacOS with the following command `tincd -n testnetwork`. Please look into tinc's documentation on how to daemonize to run on startup.

