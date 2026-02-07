package mobile

import (
	"context"
	"io"
	"net"
	"net/http"

	"github.com/xjasonlyu/tun2socks/v2/log"
	"golang.org/x/net/proxy"
)

func startHTTPProxy() {
	server := &http.Server{
		Addr: ":7778",
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodConnect {
				handleHTTPS(w, r)
			} else {
				handleHTTP(w, r)
			}
		}),
	}

	go func() {
		log.Infof("[HTTP-Proxy] Listening on :7778 -> SOCKS5 :7777")
		if err := server.ListenAndServe(); err != nil {
			log.Errorf("[HTTP-Proxy] Failed: %v", err)
		}
	}()
}

func handleHTTPS(w http.ResponseWriter, r *http.Request) {
	destConn, err := dialSOCKS5(r.Host)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer destConn.Close()

	w.WriteHeader(http.StatusOK)
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		return
	}
	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		return
	}
	defer clientConn.Close()

	pipe(destConn, clientConn)
}

func handleHTTP(w http.ResponseWriter, r *http.Request) {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialSOCKS5(addr)
		},
	}
	
	resp, err := transport.RoundTrip(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	copyHeader(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func dialSOCKS5(addr string) (net.Conn, error) {
	// Connect to local SOCKS5 (LoadBalancer/Hysteria)
	dialer, err := proxy.SOCKS5("tcp", "127.0.0.1:7777", nil, proxy.Direct)
	if err != nil {
		return nil, err
	}
	return dialer.Dial("tcp", addr)
}

func pipe(c1, c2 net.Conn) {
	ch := make(chan struct{}, 2)
	go func() {
		io.Copy(c1, c2)
		c1.(*net.TCPConn).CloseWrite()
		ch <- struct{}{}
	}()
	go func() {
		io.Copy(c2, c1)
		c2.(*net.TCPConn).CloseWrite()
		ch <- struct{}{}
	}()
	<-ch
}

func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}
