package badvpn

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/dialer"
	"github.com/xjasonlyu/tun2socks/v2/log"
)

const (
	flagKeepAlive = 0x01
	flagIPv6      = 0x08
	headerSize    = 3 // Flags(1) + ConnID(2)
)

// Packet represents a UDP packet received from UDPGW
type Packet struct {
	Addr net.Addr
	Data []byte
}

// Client handles a single UDPGW session over a shared TCP connection.
type Client struct {
	connID  uint16
	manager *Manager
	packets chan *Packet
	closed  bool
	mu      sync.Mutex
}

func (c *Client) WriteUDPGW(dstIP net.IP, dstPort uint16, data []byte) error {
	return c.manager.writePacket(c.connID, dstIP, dstPort, data)
}

func (c *Client) ReadUDPGW() (*Packet, error) {
	p, ok := <-c.packets
	if !ok {
		return nil, io.EOF
	}
	return p, nil
}

func (c *Client) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	c.closed = true
	c.manager.removeClient(c.connID)
	// Don't close channel here immediately to avoid panic on send?
	// Better let manager handle it or ensure synchronization.
	// For simplicity in this logic:
	// close(c.packets) // Removed to prevent race
	return nil
}

// Manager manages a single TCP connection to the UDPGW server and multiplexes multiple clients.
type Manager struct {
	serverAddr string
	conn       net.Conn
	clients    map[uint16]*Client
	nextID     uint16
	mu         sync.Mutex
	ctx        context.Context
	cancel     context.CancelFunc
}

func NewManager(serverAddr string) *Manager {
	ctx, cancel := context.WithCancel(context.Background())
	m := &Manager{
		serverAddr: serverAddr,
		clients:    make(map[uint16]*Client),
		nextID:     1,
		ctx:        ctx,
		cancel:     cancel,
	}
	// Start background loops
	go m.mainLoop()
	go m.keepAliveLoop()
	return m
}

func (m *Manager) StartClient() error {
	// Already started in NewManager but keeping method for explicit control if needed
	// For now, it's just a placeholder or can be used to restart logic if refactored
	return nil
}

func (m *Manager) Close() {
	m.cancel()
	m.mu.Lock()
	if m.conn != nil {
		m.conn.Close()
		m.conn = nil
	}
	m.mu.Unlock()
}

func (m *Manager) NewClient() (*Client, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	id := m.nextID
	m.nextID++
	if m.nextID == 0 {
		m.nextID = 1
	}

	// Ensure ID uniqueness/collision handling if needed
	// For now assume simple wrap around is fine for low concurrency

	client := &Client{
		connID:  id,
		manager: m,
		packets: make(chan *Packet, 100),
	}
	m.clients[id] = client
	return client, nil
}

func (m *Manager) removeClient(id uint16) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.clients, id)
}

func (m *Manager) mainLoop() {
	for {
		select {
		case <-m.ctx.Done():
			return
		default:
		}

		conn, err := dialer.DefaultDialer.DialContext(m.ctx, "tcp", m.serverAddr)
		if err != nil {
			log.Warnf("[UDPGW] Failed to connect to %s: %v, retrying in 5s...", m.serverAddr, err)
			select {
			case <-m.ctx.Done():
				return
			case <-time.After(5 * time.Second):
				continue
			}
		}

		m.mu.Lock()
		m.conn = conn
		m.mu.Unlock()

		log.Infof("[UDPGW] Connected to %s", m.serverAddr)

		// Run readLoop synchronously. It returns when connection breaks.
		m.readLoop()

		m.mu.Lock()
		if m.conn != nil {
			m.conn.Close()
			m.conn = nil
		}
		m.mu.Unlock()

		log.Warnf("[UDPGW] Connection lost, reconnecting...")
		time.Sleep(1 * time.Second)
	}
}

func (m *Manager) writePacket(connID uint16, dstIP net.IP, dstPort uint16, data []byte) error {
	m.mu.Lock()
	conn := m.conn
	m.mu.Unlock()

	if conn == nil {
		return fmt.Errorf("not connected")
	}

	isIPv6 := dstIP.To4() == nil
	var addrLen int
	if isIPv6 {
		addrLen = 16
	} else {
		addrLen = 4
	}

	packetSize := headerSize + addrLen + 2 + len(data)
	buf := make([]byte, 2+packetSize)

	// Size
	binary.LittleEndian.PutUint16(buf[0:2], uint16(packetSize))

	// Flags
	var flags uint8
	if isIPv6 {
		flags |= flagIPv6
	}
	buf[2] = flags

	// ConnID
	binary.LittleEndian.PutUint16(buf[3:5], connID)

	// Address & Data
	if isIPv6 {
		copy(buf[5:21], dstIP.To16())
		binary.BigEndian.PutUint16(buf[21:23], dstPort)
		copy(buf[23:], data)
	} else {
		copy(buf[5:9], dstIP.To4())
		binary.BigEndian.PutUint16(buf[9:11], dstPort)
		copy(buf[11:], data)
	}

	_, err := conn.Write(buf)
	return err
}

func (m *Manager) readLoop() {
	for {
		select {
		case <-m.ctx.Done():
			return
		default:
		}

		// Read Size
		sizeBuf := make([]byte, 2)
		if _, err := io.ReadFull(m.conn, sizeBuf); err != nil {
			return
		}
		totalSize := binary.LittleEndian.Uint16(sizeBuf)

		// Read Payload
		payload := make([]byte, totalSize)
		if _, err := io.ReadFull(m.conn, payload); err != nil {
			return
		}

		flags := payload[0]
		connID := binary.LittleEndian.Uint16(payload[1:3])

		if flags&flagKeepAlive != 0 {
			continue
		}

		var addrLen int
		if flags&flagIPv6 != 0 {
			addrLen = 16
		} else {
			addrLen = 4
		}

		headerEnd := 3 + addrLen + 2
		if int(totalSize) < headerEnd {
			continue
		}

		ip := make(net.IP, addrLen)
		copy(ip, payload[3:3+addrLen])
		port := binary.BigEndian.Uint16(payload[3+addrLen : 3+addrLen+2])
		data := payload[headerEnd:]

		m.mu.Lock()
		client, ok := m.clients[connID]
		m.mu.Unlock()

		if ok {
			select {
			case client.packets <- &Packet{
				Addr: &net.UDPAddr{IP: ip, Port: int(port)},
				Data: data,
			}:
			default:
				// Buffer full, drop
			}
		}
	}
}

func (m *Manager) keepAliveLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-m.ctx.Done():
			return
		case <-ticker.C:
			m.mu.Lock()
			conn := m.conn
			m.mu.Unlock()

			if conn != nil {
				// KeepAlive Packet: Size(3) + Flags(1) + ID(2)
				// Flags = 0x01
				buf := make([]byte, 2+headerSize)
				binary.LittleEndian.PutUint16(buf[0:2], uint16(headerSize))
				buf[2] = flagKeepAlive
				binary.LittleEndian.PutUint16(buf[3:5], 0)
				conn.Write(buf)
			}
		}
	}
}