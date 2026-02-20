import { useState, useRef, useEffect } from 'react';

/**
 * ChatPane — message thread for Alice or Bob with input field.
 */
export default function ChatPane({ alias, messages, onSend, onPing, onFetch, loading }) {
  const [input, setInput] = useState('');
  const scrollRef = useRef(null);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSend = (e) => {
    e.preventDefault();
    if (!input.trim() || loading) return;
    onSend(input.trim());
    setInput('');
  };

  const other = alias === 'Alice' ? 'Bob' : 'Alice';

  return (
    <div className="flex-1 flex flex-col min-h-0">
      {/* Action buttons */}
      <div className="px-3 py-2 border-b border-gray-800 flex gap-2">
        <button
          onClick={onPing}
          disabled={loading}
          className="text-xs px-2 py-1 bg-purple-900/50 text-purple-300 rounded hover:bg-purple-900 disabled:opacity-50 transition"
        >
          🏓 Ping {other}
        </button>
        <button
          onClick={onFetch}
          disabled={loading}
          className="text-xs px-2 py-1 bg-gray-800 text-gray-300 rounded hover:bg-gray-700 disabled:opacity-50 transition"
        >
          📥 Fetch
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-3 space-y-2">
        {messages.length === 0 && (
          <p className="text-xs text-gray-600 text-center mt-8">
            No messages yet. Send one!
          </p>
        )}
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`max-w-[85%] ${
              msg.self ? 'ml-auto' : 'mr-auto'
            }`}
          >
            <div
              className={`rounded-lg px-3 py-2 text-sm ${
                msg.self
                  ? 'bg-blue-900/60 text-blue-100'
                  : 'bg-gray-800 text-gray-200'
              }`}
            >
              <div className="flex items-center gap-2 mb-1">
                <span className="text-[10px] font-semibold text-gray-400">
                  {msg.from}
                </span>
                <span className="text-[10px] text-gray-600">
                  {new Date(msg.timestamp).toLocaleTimeString()}
                </span>
              </div>
              <p>{msg.body}</p>
            </div>
          </div>
        ))}
        <div ref={scrollRef} />
      </div>

      {/* Input */}
      <form
        onSubmit={handleSend}
        className="p-3 border-t border-gray-800 flex gap-2"
      >
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder={`Message as ${alias}…`}
          disabled={loading}
          className="flex-1 bg-gray-800 rounded px-3 py-2 text-sm text-gray-100 placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-blue-500 disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={loading || !input.trim()}
          className="px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition"
        >
          Send
        </button>
      </form>
    </div>
  );
}
