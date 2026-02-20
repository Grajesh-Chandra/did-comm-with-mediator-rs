import { useState, useCallback } from 'react';

/**
 * PacketInspector — the centrepiece panel.
 * Renders a live feed of PacketEvent cards with collapsible JSON.
 */

const STEP_COLORS = {
  plaintext_message: { bg: 'bg-blue-900/30', border: 'border-blue-700', badge: 'bg-blue-700 text-blue-100' },
  signed_envelope:   { bg: 'bg-yellow-900/30', border: 'border-yellow-700', badge: 'bg-yellow-700 text-yellow-100' },
  encrypted_payload: { bg: 'bg-red-900/30', border: 'border-red-700', badge: 'bg-red-700 text-red-100' },
  encrypted_forward: { bg: 'bg-red-900/30', border: 'border-red-800', badge: 'bg-red-800 text-red-100' },
  mediator_send:     { bg: 'bg-orange-900/30', border: 'border-orange-700', badge: 'bg-orange-700 text-orange-100' },
  mediator_ack:      { bg: 'bg-green-900/30', border: 'border-green-700', badge: 'bg-green-700 text-green-100' },
  trust_ping:        { bg: 'bg-purple-900/30', border: 'border-purple-700', badge: 'bg-purple-700 text-purple-100' },
  trust_pong:        { bg: 'bg-purple-900/30', border: 'border-purple-600', badge: 'bg-purple-600 text-purple-100' },
  message_pickup:    { bg: 'bg-green-900/30', border: 'border-green-800', badge: 'bg-green-800 text-green-100' },
  message_delivery:  { bg: 'bg-green-900/30', border: 'border-green-600', badge: 'bg-green-600 text-green-100' },
};

function didAlias(did) {
  if (!did) return '?';
  if (did === 'mediator' || did === 'system') return did;
  if (did.includes('alice') || did.toLowerCase().includes('alice')) return 'Alice';
  if (did.includes('bob') || did.toLowerCase().includes('bob')) return 'Bob';
  // For real DIDs, show shortened version
  return did.length > 20 ? `${did.slice(0, 12)}…` : did;
}

function PacketCard({ packet }) {
  const [expanded, setExpanded] = useState(false);
  const [copied, setCopied] = useState(false);

  const style = STEP_COLORS[packet.step] || STEP_COLORS.plaintext_message;
  const direction = packet.direction === 'outbound' ? '→' : '←';
  const jsonStr = JSON.stringify(packet.raw_json, null, 2);

  const copyToClipboard = useCallback(() => {
    navigator.clipboard.writeText(jsonStr).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  }, [jsonStr]);

  return (
    <div
      className={`packet-enter rounded-lg border ${style.border} ${style.bg} overflow-hidden`}
    >
      {/* Header */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-4 py-3 flex items-center gap-3 text-left hover:bg-white/5 transition"
      >
        <span className={`text-[10px] font-bold px-2 py-0.5 rounded ${style.badge}`}>
          {packet.label}
        </span>
        <span className="text-xs text-gray-300 flex-1">
          <span className="font-medium">{didAlias(packet.from)}</span>
          <span className="mx-1 text-gray-500">{direction}</span>
          <span className="font-medium">{didAlias(packet.to)}</span>
        </span>
        <span className="text-[10px] text-gray-500">
          {new Date(packet.timestamp).toLocaleTimeString()}
        </span>
        <span className="text-gray-500 text-xs">
          {expanded ? '▲' : '▼'}
        </span>
      </button>

      {/* Expanded JSON */}
      {expanded && (
        <div className="border-t border-gray-800 relative">
          <div className="absolute top-2 right-2 flex gap-1">
            <button
              onClick={copyToClipboard}
              className="text-[10px] px-2 py-0.5 bg-gray-700 text-gray-300 rounded hover:bg-gray-600 transition"
            >
              {copied ? '✓ Copied' : '📋 Copy'}
            </button>
          </div>
          <pre className="p-4 text-xs text-gray-300 overflow-x-auto max-h-80 overflow-y-auto font-mono leading-relaxed">
            {jsonStr}
          </pre>
        </div>
      )}
    </div>
  );
}

export default function PacketInspector({ packets }) {
  const [filter, setFilter] = useState('all');

  const filteredPackets =
    filter === 'all'
      ? packets
      : packets.filter((p) => p.step === filter);

  const stepCounts = packets.reduce((acc, p) => {
    acc[p.step] = (acc[p.step] || 0) + 1;
    return acc;
  }, {});

  return (
    <div className="flex flex-col h-full">
      {/* Toolbar */}
      <div className="px-4 py-3 border-b border-gray-800 flex items-center gap-4">
        <h2 className="text-sm font-bold text-white">📡 Packet Inspector</h2>
        <span className="text-xs text-gray-500">
          {packets.length} event{packets.length !== 1 ? 's' : ''}
        </span>
        <div className="flex-1" />
        <select
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="text-xs bg-gray-800 text-gray-300 rounded px-2 py-1 border border-gray-700 focus:outline-none"
        >
          <option value="all">All Steps</option>
          <option value="plaintext_message">① Plaintext</option>
          <option value="signed_envelope">② Signed</option>
          <option value="encrypted_payload">③ Encrypted</option>
          <option value="encrypted_forward">④ Forward</option>
          <option value="mediator_send">⑤ Send</option>
          <option value="mediator_ack">⑤ ACK</option>
          <option value="trust_ping">Ping</option>
          <option value="trust_pong">Pong</option>
          <option value="message_pickup">⑥ Pickup</option>
          <option value="message_delivery">⑥ Delivery</option>
        </select>
      </div>

      {/* Packet list */}
      <div className="flex-1 overflow-y-auto p-4 space-y-2">
        {filteredPackets.length === 0 ? (
          <div className="text-center text-gray-600 mt-12">
            <p className="text-4xl mb-3">📦</p>
            <p className="text-sm">No packets yet.</p>
            <p className="text-xs mt-1">
              Send a message or trust ping to see DIDComm packets appear here in real time.
            </p>
          </div>
        ) : (
          filteredPackets.map((pkt) => (
            <PacketCard key={pkt.id} packet={pkt} />
          ))
        )}
      </div>
    </div>
  );
}
