import { useState } from 'react';

/**
 * ControlPanel — demo controls in the header bar.
 */
export default function ControlPanel({ loading, onSend, onPing, onReset }) {
  const [showSend, setShowSend] = useState(false);
  const [from, setFrom] = useState('alice');
  const [to, setTo] = useState('bob');
  const [body, setBody] = useState('');

  const handleSend = () => {
    if (!body.trim()) return;
    onSend(from, to, body.trim());
    setBody('');
    setShowSend(false);
  };

  return (
    <div className="flex items-center gap-2 relative">
      {/* Quick Send */}
      <button
        onClick={() => setShowSend(!showSend)}
        className="text-xs px-3 py-1.5 bg-blue-600 text-white rounded hover:bg-blue-500 disabled:opacity-50 transition"
        disabled={loading}
      >
        💬 Send Message
      </button>

      {/* Trust Ping buttons */}
      <button
        onClick={() => onPing('alice', 'bob')}
        disabled={loading}
        className="text-xs px-3 py-1.5 bg-purple-700 text-white rounded hover:bg-purple-600 disabled:opacity-50 transition"
      >
        🏓 Alice → Bob Ping
      </button>

      <button
        onClick={() => onPing('alice', 'mediator')}
        disabled={loading}
        className="text-xs px-3 py-1.5 bg-purple-800 text-white rounded hover:bg-purple-700 disabled:opacity-50 transition"
      >
        🏓 Ping Mediator
      </button>

      {/* Reset */}
      <button
        onClick={onReset}
        className="text-xs px-3 py-1.5 bg-gray-700 text-gray-300 rounded hover:bg-gray-600 transition"
      >
        🔄 Reset
      </button>

      {/* Send Message Dropdown */}
      {showSend && (
        <div className="absolute top-full right-0 mt-2 bg-gray-800 border border-gray-700 rounded-lg shadow-xl p-4 w-80 z-50">
          <h3 className="text-sm font-bold text-white mb-3">Send DIDComm Message</h3>

          <div className="flex gap-2 mb-3">
            <div className="flex-1">
              <label className="text-[10px] text-gray-500 uppercase">From</label>
              <select
                value={from}
                onChange={(e) => {
                  setFrom(e.target.value);
                  setTo(e.target.value === 'alice' ? 'bob' : 'alice');
                }}
                className="w-full mt-0.5 bg-gray-700 text-gray-200 rounded px-2 py-1 text-xs border border-gray-600"
              >
                <option value="alice">Alice</option>
                <option value="bob">Bob</option>
              </select>
            </div>
            <div className="flex items-end pb-1 text-gray-500 text-sm">→</div>
            <div className="flex-1">
              <label className="text-[10px] text-gray-500 uppercase">To</label>
              <select
                value={to}
                onChange={(e) => setTo(e.target.value)}
                className="w-full mt-0.5 bg-gray-700 text-gray-200 rounded px-2 py-1 text-xs border border-gray-600"
              >
                <option value="alice">Alice</option>
                <option value="bob">Bob</option>
              </select>
            </div>
          </div>

          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Message body…"
            rows={3}
            className="w-full bg-gray-700 text-gray-200 rounded px-3 py-2 text-xs border border-gray-600 focus:outline-none focus:ring-1 focus:ring-blue-500 resize-none mb-3"
          />

          <div className="flex gap-2 justify-end">
            <button
              onClick={() => setShowSend(false)}
              className="text-xs px-3 py-1.5 bg-gray-700 text-gray-300 rounded hover:bg-gray-600 transition"
            >
              Cancel
            </button>
            <button
              onClick={handleSend}
              disabled={!body.trim() || loading}
              className="text-xs px-3 py-1.5 bg-blue-600 text-white rounded hover:bg-blue-500 disabled:opacity-50 transition"
            >
              Send
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
