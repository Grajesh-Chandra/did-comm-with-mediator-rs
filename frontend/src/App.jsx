import { useState, useEffect, useRef, useCallback } from 'react';
import IdentityCard from './components/IdentityCard';
import ChatPane from './components/ChatPane';
import PacketInspector from './components/PacketInspector';
import FlowDiagram from './components/FlowDiagram';
import ControlPanel from './components/ControlPanel';

const API_BASE = '/api';

export default function App() {
  const [identities, setIdentities] = useState(null);
  const [packets, setPackets] = useState([]);
  const [messages, setMessages] = useState({ alice: [], bob: [] });
  const [loading, setLoading] = useState(false);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState(null);
  const eventSourceRef = useRef(null);
  const identitiesRef = useRef(null);

  // Fetch identities on mount
  useEffect(() => {
    fetch(`${API_BASE}/identities`)
      .then((r) => r.json())
      .then((ids) => {
        setIdentities(ids);
        identitiesRef.current = ids;
      })
      .catch((e) => setError(`Failed to load identities: ${e.message}`));
  }, []);

  // SSE connection for live packet stream
  useEffect(() => {
    const es = new EventSource(`${API_BASE}/packets/stream`);
    eventSourceRef.current = es;

    es.addEventListener('packet', (e) => {
      try {
        const pkt = JSON.parse(e.data);
        // Handle reset events
        if (pkt.raw_json?.action === 'reset') {
          setPackets([]);
          setMessages({ alice: [], bob: [] });
          return;
        }
        setPackets((prev) => [pkt, ...prev]);
      } catch {
        // ignore parse errors
      }
    });

    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);

    return () => es.close();
  }, []);

  const sendMessage = useCallback(async (from, to, body) => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/messages/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to, body }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Send failed');

      const ts = new Date().toISOString();
      const corrId = data.correlation_id || Date.now().toString();
      const senderAlias = from.toLowerCase();
      const recipientAlias = to.toLowerCase();
      const senderName = from.charAt(0).toUpperCase() + from.slice(1);

      // Add to sender's chat (sent message) AND recipient's chat (received)
      setMessages((prev) => ({
        ...prev,
        [senderAlias]: [
          ...prev[senderAlias],
          {
            id: corrId + '-sent',
            from: senderName,
            body,
            timestamp: ts,
            correlationId: corrId,
            self: true,
          },
        ],
        [recipientAlias]: [
          ...prev[recipientAlias],
          {
            id: corrId + '-recv',
            from: senderName,
            body,
            timestamp: ts,
            correlationId: corrId,
          },
        ],
      }));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  const sendPing = useCallback(async (from, to) => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API_BASE}/ping`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Ping failed');
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchMessages = useCallback(async (alias) => {
    try {
      const res = await fetch(`${API_BASE}/messages/${alias}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Fetch failed');
      return data.messages;
    } catch (e) {
      setError(e.message);
      return [];
    }
  }, []);

  const resetDemo = useCallback(async () => {
    try {
      await fetch(`${API_BASE}/reset`, { method: 'POST' });
      setPackets([]);
      setMessages({ alice: [], bob: [] });
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  return (
    <div className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="bg-gray-900 border-b border-gray-800 px-6 py-4">
        <div className="flex items-center justify-between max-w-screen-2xl mx-auto">
          <div className="flex items-center gap-3">
            <span className="text-2xl">🔐</span>
            <div>
              <h1 className="text-xl font-bold text-white">
                DIDComm v2.1 P2P Demo
              </h1>
              <p className="text-sm text-gray-400">
                Self-Hosted Affinidi Mediator — Packet Inspector
              </p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 text-sm">
              <span
                className={`inline-block w-2 h-2 rounded-full ${
                  connected ? 'bg-green-400 status-pulse' : 'bg-red-500'
                }`}
              />
              <span className="text-gray-400">
                {connected ? 'SSE Connected' : 'Disconnected'}
              </span>
            </div>
            <ControlPanel
              loading={loading}
              onSend={sendMessage}
              onPing={sendPing}
              onReset={resetDemo}
            />
          </div>
        </div>
      </header>

      {/* Error banner */}
      {error && (
        <div className="bg-red-900/50 border-b border-red-800 px-6 py-2 text-red-300 text-sm">
          ⚠ {error}
          <button
            className="ml-4 underline"
            onClick={() => setError(null)}
          >
            dismiss
          </button>
        </div>
      )}

      {/* Flow Diagram */}
      <div className="bg-gray-900/50 border-b border-gray-800">
        <FlowDiagram packets={packets} />
      </div>

      {/* Main 3-column layout */}
      <main className="flex-1 flex overflow-hidden max-w-screen-2xl mx-auto w-full">
        {/* Alice */}
        <div className="w-80 flex-shrink-0 border-r border-gray-800 flex flex-col">
          <IdentityCard identity={identities?.alice} connected={connected} />
          <ChatPane
            alias="Alice"
            messages={messages.alice}
            onSend={(body) => sendMessage('alice', 'bob', body)}
            onPing={() => sendPing('alice', 'bob')}
            onFetch={() => fetchMessages('alice')}
            loading={loading}
          />
        </div>

        {/* Packet Inspector */}
        <div className="flex-1 flex flex-col min-w-0">
          <PacketInspector packets={packets} />
        </div>

        {/* Bob */}
        <div className="w-80 flex-shrink-0 border-l border-gray-800 flex flex-col">
          <IdentityCard identity={identities?.bob} connected={connected} />
          <ChatPane
            alias="Bob"
            messages={messages.bob}
            onSend={(body) => sendMessage('bob', 'alice', body)}
            onPing={() => sendPing('bob', 'alice')}
            onFetch={() => fetchMessages('bob')}
            loading={loading}
          />
        </div>
      </main>
    </div>
  );
}
