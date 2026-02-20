import { useMemo } from 'react';

/**
 * FlowDiagram — animated SVG sequence diagram showing packet flow.
 * Alice → Mediator → Bob with labeled arrows that light up as packets arrive.
 */

const ACTORS = [
  { key: 'alice', label: 'Alice', x: 120, color: '#3b82f6' },
  { key: 'mediator', label: 'Mediator', x: 400, color: '#f59e0b' },
  { key: 'bob', label: 'Bob', x: 680, color: '#10b981' },
];

function classifyActor(did) {
  if (!did) return null;
  const d = did.toLowerCase();
  if (d === 'mediator' || d === 'system') return 'mediator';
  if (d.includes('alice') || d === 'alice') return 'alice';
  if (d.includes('bob') || d === 'bob') return 'bob';
  return 'mediator'; // default to mediator for unknown DIDs
}

function stepColor(step) {
  const map = {
    plaintext_message: '#3b82f6',
    signed_envelope:   '#eab308',
    encrypted_payload: '#ef4444',
    encrypted_forward: '#dc2626',
    mediator_send:     '#f97316',
    mediator_ack:      '#22c55e',
    trust_ping:        '#a855f7',
    trust_pong:        '#8b5cf6',
    message_pickup:    '#14b8a6',
    message_delivery:  '#22c55e',
  };
  return map[step] || '#6b7280';
}

export default function FlowDiagram({ packets }) {
  // Show last 5 arrows
  const recentPackets = useMemo(() => packets.slice(0, 5).reverse(), [packets]);

  const arrows = recentPackets.map((pkt, i) => {
    const fromActor = classifyActor(pkt.from);
    const toActor = classifyActor(pkt.to);
    const fromX = ACTORS.find((a) => a.key === fromActor)?.x || 400;
    const toX = ACTORS.find((a) => a.key === toActor)?.x || 400;
    if (fromX === toX) return null;

    const y = 70 + i * 18;
    const color = stepColor(pkt.step);
    const label = pkt.label?.replace(/[①②③④⑤⑥]\s*/, '') || pkt.step;

    return { fromX, toX, y, color, label, id: pkt.id };
  }).filter(Boolean);

  return (
    <div className="px-6 py-3">
      <svg viewBox="0 0 800 170" className="w-full h-28" preserveAspectRatio="xMidYMid meet">
        {/* Background */}
        <defs>
          <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
            <polygon points="0 0, 8 3, 0 6" fill="#9ca3af" />
          </marker>
        </defs>

        {/* Actor lifelines */}
        {ACTORS.map((actor) => (
          <g key={actor.key}>
            <line
              x1={actor.x}
              y1={42}
              x2={actor.x}
              y2={165}
              stroke={actor.color}
              strokeWidth="1"
              opacity="0.3"
              strokeDasharray="4 4"
            />
            <rect
              x={actor.x - 45}
              y={8}
              width={90}
              height={28}
              rx={6}
              fill={actor.color}
              opacity="0.15"
              stroke={actor.color}
              strokeWidth="1"
            />
            <text
              x={actor.x}
              y={26}
              textAnchor="middle"
              fill={actor.color}
              fontSize="12"
              fontWeight="bold"
            >
              {actor.label}
            </text>
          </g>
        ))}

        {/* Arrows */}
        {arrows.map((arrow) => (
          <g key={arrow.id} className="arrow-animate">
            <line
              x1={arrow.fromX}
              y1={arrow.y}
              x2={arrow.toX}
              y2={arrow.y}
              stroke={arrow.color}
              strokeWidth="2"
              markerEnd="url(#arrowhead)"
            />
            <text
              x={(arrow.fromX + arrow.toX) / 2}
              y={arrow.y - 4}
              textAnchor="middle"
              fill={arrow.color}
              fontSize="9"
              fontWeight="500"
            >
              {arrow.label}
            </text>
          </g>
        ))}

        {/* Empty state */}
        {arrows.length === 0 && (
          <text x="400" y="110" textAnchor="middle" fill="#4b5563" fontSize="12">
            Waiting for packets…
          </text>
        )}
      </svg>
    </div>
  );
}
