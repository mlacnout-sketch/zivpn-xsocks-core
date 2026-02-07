package tunnel

import (
	"net"
	"testing"

	"github.com/stretchr/testify/assert"
	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"net/netip"
)

// Mock PacketConn
type mockPacketConn struct {
	net.PacketConn
	readPacket []byte
	readAddr   net.Addr
}

func (m *mockPacketConn) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	if m.readPacket == nil {
		return 0, nil, nil // Block or EOF in real mock
	}
	copy(p, m.readPacket)
	return len(m.readPacket), m.readAddr, nil
}

func TestRestrictedNATPacketConn_ReadFrom(t *testing.T) {
	// Destination (Expected)
	dstIP := netip.MustParseAddr("8.8.8.8")
	dstPort := uint16(53)
	
	meta := &M.Metadata{
		DstIP:   dstIP,
		DstPort: dstPort,
	}

	tests := []struct {
		name        string
		srcAddr     net.Addr
		shouldDrop  bool
	}{
		{
			name: "Same IP, Same Port (Symmetric Match)",
			srcAddr: &net.UDPAddr{IP: net.ParseIP("8.8.8.8"), Port: 53},
			shouldDrop: false,
		},
		{
			name: "Same IP, Diff Port (Restricted Cone Match)",
			srcAddr: &net.UDPAddr{IP: net.ParseIP("8.8.8.8"), Port: 9999},
			shouldDrop: false,
		},
		{
			name: "Diff IP (Should Drop)",
			srcAddr: &net.UDPAddr{IP: net.ParseIP("1.1.1.1"), Port: 53},
			shouldDrop: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Mock underlying conn
			mockPC := &mockPacketConn{
				readPacket: []byte("test"),
				readAddr:   tt.srcAddr,
			}

			// Create restricted NAT conn
			rn := newRestrictedNATPacketConn(mockPC, meta)

			// Read
			buf := make([]byte, 1024)
			// ReadFrom loop in implementation handles drop by continue.
			// In unit test with simple mock, if it continues, it will call ReadFrom again.
			// To prevent infinite loop in test if logic is wrong (always drop), we need a smarter mock or limited read.
			
			// But wait, my implementation of ReadFrom has a loop:
			// for { n, from, err := pc.PacketConn.ReadFrom(p) ... if drop continue ... return }
			
			// If we mock ReadFrom to return ONCE, then loop will call it again.
			// We need mock to return EOF or Error on second call to break loop if dropped.
			
			// Let's refine mock:
			// Override ReadFrom with closure-based mock? No, can't easily override method of struct.
			// Let's make mock struct smarter.
			smartMock := &smartMockPacketConn{
				data: []byte("test"),
				addr: tt.srcAddr,
			}
			
			rn = newRestrictedNATPacketConn(smartMock, meta)
			
			n, addr, err := rn.ReadFrom(buf)
			
			if tt.shouldDrop {
				// If dropped, the loop continues and calls ReadFrom again.
				// Smart mock returns error on 2nd call.
				// So we expect err != nil (or EOF)
				assert.Error(t, err)
			} else {
				// If accepted, it returns immediately
				assert.NoError(t, err)
				assert.Equal(t, 4, n)
				assert.Equal(t, tt.srcAddr, addr)
			}
		})
	}
}

type smartMockPacketConn struct {
	net.PacketConn
	data []byte
	addr net.Addr
	calls int
}

func (m *smartMockPacketConn) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	m.calls++
	if m.calls > 1 {
		return 0, nil, net.ErrClosed
	}
	copy(p, m.data)
	return len(m.data), m.addr, nil
}
