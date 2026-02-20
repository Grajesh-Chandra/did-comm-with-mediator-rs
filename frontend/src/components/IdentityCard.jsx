/**
 * IdentityCard — shows DID string, key types, and connection status.
 */
export default function IdentityCard({ identity, connected }) {
  if (!identity) {
    return (
      <div className="p-4 border-b border-gray-800 animate-pulse">
        <div className="h-4 bg-gray-800 rounded w-24 mb-2" />
        <div className="h-3 bg-gray-800 rounded w-full" />
      </div>
    );
  }

  const shortDid =
    identity.did.length > 40
      ? `${identity.did.slice(0, 20)}...${identity.did.slice(-12)}`
      : identity.did;

  return (
    <div className="p-4 border-b border-gray-800">
      <div className="flex items-center justify-between mb-2">
        <h2 className="text-lg font-bold text-white">{identity.alias}</h2>
        <span
          className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full ${
            connected
              ? 'bg-green-900/50 text-green-400'
              : 'bg-red-900/50 text-red-400'
          }`}
        >
          <span
            className={`w-1.5 h-1.5 rounded-full ${
              connected ? 'bg-green-400' : 'bg-red-500'
            }`}
          />
          {connected ? 'Online' : 'Offline'}
        </span>
      </div>

      <div className="space-y-1">
        <div className="text-xs text-gray-500 font-mono" title={identity.did}>
          {shortDid}
        </div>
        <div className="flex flex-wrap gap-1 mt-1">
          {identity.key_types?.map((kt) => (
            <span
              key={kt}
              className="text-[10px] bg-gray-800 text-gray-400 px-1.5 py-0.5 rounded"
            >
              {kt}
            </span>
          ))}
        </div>
        {identity.mediator_did && (
          <div className="text-[10px] text-gray-600 mt-1 truncate" title={identity.mediator_did}>
            Mediator: {identity.mediator_did.slice(0, 30)}…
          </div>
        )}
      </div>
    </div>
  );
}
