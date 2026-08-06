#!/bin/bash

socat -v -d -d PTY,link=/tmp/altirra-tty,raw,echo=0 TCP:127.0.0.1:9000

