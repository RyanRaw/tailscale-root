// tsdns: 极简 DNS 转发器（UDP + TCP），仅供本机回环使用。
//
// 背景：本模块打包的 tailscaled 是 CGO_ENABLED=0 的静态 Go 二进制，解析域名时
// 不走 bionic/netd，只读 /etc/resolv.conf。Android 没有这个文件，Go 运行时会退回
// defaultNS = ["127.0.0.1:53", "[::1]:53"]（见 src/net/dnsconfig.go）。只要这个
// 地址上有可用的 DNS，tailscaled 就能正常解析，不必改动 /system 下任何文件。
//
// 用法：tsdns -listen 127.0.0.1:53 -upstream 223.5.5.5:53,119.29.29.29:53
package main

import (
	"encoding/binary"
	"flag"
	"io"
	"log"
	"net"
	"strings"
	"sync/atomic"
	"time"
)

var (
	listenAddr = flag.String("listen", "127.0.0.1:53", "listen address")
	upstreams  = flag.String("upstream", "223.5.5.5:53,119.29.29.29:53", "upstream DNS servers, comma separated")
	timeout    = flag.Duration("timeout", 5*time.Second, "per-query timeout")
	verbose    = flag.Bool("v", false, "log every upstream failure")
)

var (
	ups []string
	rr  uint32
)

func main() {
	flag.Parse()
	for _, s := range strings.Split(*upstreams, ",") {
		if s = strings.TrimSpace(s); s != "" {
			ups = append(ups, s)
		}
	}
	if len(ups) == 0 {
		log.Fatal("tsdns: no upstream configured")
	}
	log.Printf("tsdns: listening on %s, upstream=%v", *listenAddr, ups)

	pc, err := net.ListenPacket("udp", *listenAddr)
	if err != nil {
		log.Fatalf("tsdns: udp listen: %v", err)
	}
	go serveUDP(pc)

	ln, err := net.Listen("tcp", *listenAddr)
	if err != nil {
		log.Printf("tsdns: tcp listen: %v (udp only)", err)
	} else {
		go serveTCP(ln)
	}
	select {}
}

func nextUpstream() string {
	n := atomic.AddUint32(&rr, 1)
	return ups[int(n)%len(ups)]
}

func serveUDP(pc net.PacketConn) {
	buf := make([]byte, 4096)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			return
		}
		q := make([]byte, n)
		copy(q, buf[:n])
		go func(q []byte, addr net.Addr) {
			resp, err := exchangeUDP(q)
			if err != nil {
				if *verbose {
					log.Printf("tsdns: udp query failed: %v", err)
				}
				return
			}
			pc.WriteTo(resp, addr)
		}(q, addr)
	}
}

func exchangeUDP(q []byte) ([]byte, error) {
	var lastErr error
	for i := 0; i < len(ups); i++ {
		up := nextUpstream()
		conn, err := net.DialTimeout("udp", up, *timeout)
		if err != nil {
			lastErr = err
			continue
		}
		conn.SetDeadline(time.Now().Add(*timeout))
		if _, err = conn.Write(q); err != nil {
			conn.Close()
			lastErr = err
			continue
		}
		buf := make([]byte, 4096)
		m, err := conn.Read(buf)
		conn.Close()
		if err != nil {
			lastErr = err
			continue
		}
		return buf[:m], nil
	}
	return nil, lastErr
}

func serveTCP(ln net.Listener) {
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go handleTCP(c)
	}
}

func handleTCP(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(*timeout))
	for {
		var l [2]byte
		if _, err := io.ReadFull(c, l[:]); err != nil {
			return
		}
		n := binary.BigEndian.Uint16(l[:])
		if n == 0 {
			return
		}
		q := make([]byte, n)
		if _, err := io.ReadFull(c, q); err != nil {
			return
		}
		resp, err := exchangeTCP(q)
		if err != nil || len(resp) == 0 {
			if *verbose && err != nil {
				log.Printf("tsdns: tcp query failed: %v", err)
			}
			return
		}
		var out [2]byte
		binary.BigEndian.PutUint16(out[:], uint16(len(resp)))
		c.Write(out[:])
		c.Write(resp)
	}
}

func exchangeTCP(q []byte) ([]byte, error) {
	var lastErr error
	for i := 0; i < len(ups); i++ {
		up := nextUpstream()
		conn, err := net.DialTimeout("tcp", up, *timeout)
		if err != nil {
			lastErr = err
			continue
		}
		conn.SetDeadline(time.Now().Add(*timeout))
		var l [2]byte
		binary.BigEndian.PutUint16(l[:], uint16(len(q)))
		if _, err = conn.Write(l[:]); err == nil {
			_, err = conn.Write(q)
		}
		if err != nil {
			conn.Close()
			lastErr = err
			continue
		}
		if _, err = io.ReadFull(conn, l[:]); err != nil {
			conn.Close()
			lastErr = err
			continue
		}
		m := binary.BigEndian.Uint16(l[:])
		buf := make([]byte, m)
		if _, err = io.ReadFull(conn, buf); err != nil {
			conn.Close()
			lastErr = err
			continue
		}
		conn.Close()
		return buf, nil
	}
	return nil, lastErr
}
