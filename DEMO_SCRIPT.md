# Demo Script — DIDComm v2.1 P2P Communication

A step-by-step walkthrough for presenting this demo to customers. Each section
builds on the previous one, progressively revealing how DIDComm works under the
hood.

---

## Before the Demo

1. **Start Redis**: `docker run --name=redis-local --publish=6379:6379 --detach redis:8.0`
2. **Start the Mediator**: `cd affinidi-messaging-mediator && cargo run`
3. **Start the Demo Backend**: `cargo run` (in this project)
4. **Start the Frontend**: `cd frontend && npm run dev`
5. **Open Browser**: Navigate to `http://localhost:5173`

Verify the SSE connection indicator in the header shows **green "SSE Connected"**.

---

## Act 1: Meet the Identities (1 min)

**What to show:** The two identity cards in the left and right columns.

**Talking points:**

> "Alice and Bob each have a **DID:Peer** identity — a self-generated
> decentralized identifier. No central authority issued these. They each carry
> multiple key types: P-256 and Ed25519 for verification (signing), and X25519
> and secp256k1 for encryption."
>
> "Notice the mediator DID shown below each identity. Both Alice and Bob are
> registered with the **same mediator** — a relay service that stores and
> forwards encrypted messages."

**Key concept:** DIDs are self-sovereign. No registration server needed.

---

## Act 2: Trust Ping (2 min)

**Action:** Click the **🏓 Alice → Bob Ping** button in the header.

**What to watch in the Packet Inspector:**

1. **① Trust Ping** (purple) — Alice constructs a DIDComm trust-ping message
2. **⑤ Mediator ACK** (green) — The mediator confirms it stored the ping
3. **② Trust Pong** (purple) — Alice receives Bob's pong response

**Talking points:**

> "A trust ping is the DIDComm equivalent of ICMP ping. Alice sends an encrypted
> ping to Bob *through the mediator*. The mediator never sees the content — it
> only knows that Alice wants to deliver something to Bob."
>
> "Expand any packet card to see the raw JSON. Notice the `ciphertext` field in
> the encrypted messages — even the mediator cannot read this."

**Key concept:** End-to-end encryption. The mediator is a blind relay.

---

## Act 3: Send a Message — The Full 6-Step Flow (5 min)

**Action:** Click **💬 Send Message**, set Alice → Bob, type "Hello Bob! This is
a secret message." and click Send.

**What to watch (each step appears in real time):**

### Step ① Plaintext Message (blue)
> "This is the message Alice *wants* to send. It's a standard DIDComm
> `basicmessage/2.0` with a JSON body. Right now it's plaintext — anyone could
> read it."

Expand the card to show the full JSON structure: `id`, `type`, `from`, `to`, `body`.

### Step ③ Encrypted Payload (red)
> "Alice encrypts the message specifically for Bob using Bob's public key.
> Only Bob's private key can decrypt this. Notice it's now a JWE (JSON Web
> Encryption) envelope with `ciphertext`, `protected`, `recipients`, and `iv`
> fields."

Expand to show the JWE structure. Point out the `recipients` array.

### Step ④ Forward Envelope (dark red)
> "Alice wraps the encrypted payload inside a **DIDComm Forward** message
> addressed to the mediator. This outer envelope is encrypted for the mediator's
> DID. The mediator can open this outer layer to see *who* the inner message is
> for, but it **cannot** read the inner payload."

This is the key architectural insight. Double encryption.

### Step ⑤ Mediator Send & ACK (orange → green)
> "The forward envelope is sent over WebSocket. The mediator confirms storage
> with an ACK. At this point the message is queued for Bob."

### Step ⑥ Pickup & Delivery (green)
> "Bob's client picks up messages via the mediator's live WebSocket stream.
> The mediator delivers the encrypted payload, Bob decrypts it, and we see the
> original plaintext message."

Expand the delivery card to show the decrypted message matches the original.

**Key concepts:**
- Double encryption (inner for recipient, outer for mediator)
- Forward routing — mediator only knows routing, not content
- Asynchronous delivery — Bob can be offline, messages queue

---

## Act 4: Bob Replies (1 min)

**Action:** Type a message in Bob's chat pane and send it to Alice.

> "The same 6-step flow happens in reverse. Bob → Mediator → Alice. Notice the
> packet inspector shows new events with Bob as the sender."

---

## Act 5: Inspect the Packets (2 min)

**Action:** Use the filter dropdown in the Packet Inspector to focus on specific steps.

- Filter to **③ Encrypted** — show that every message has a unique ciphertext
- Filter to **④ Forward** — show the routing envelopes
- Filter to **⑤ ACK** — show mediator acknowledgments

> "The Packet Inspector shows the **actual bytes on the wire**. This isn't a
> reconstruction — these are the real JWE/JWS envelopes being exchanged."

**Action:** Click the **📋 Copy** button on any packet to copy its JSON.

---

## Act 6: The Sequence Diagram (1 min)

**Action:** Point to the flow diagram at the top of the page.

> "This animated diagram shows the last 5 packets flowing between Alice,
> the Mediator, and Bob. The colours match the packet types — blue for plaintext,
> red for encrypted, green for ACKs and deliveries."

---

## Closing Points (1 min)

> "What we've demonstrated:
>
> 1. **Self-sovereign identities** — Alice and Bob generated their own DIDs
> 2. **End-to-end encryption** — the mediator never sees message content
> 3. **DIDComm v2.1 compliance** — standard protocol, interoperable
> 4. **Self-hosted mediator** — you control the infrastructure
> 5. **Asynchronous messaging** — works even when parties are offline
>
> The Affinidi Messaging SDK handles all the cryptographic heavy lifting. Your
> application just calls `pack_encrypted()`, `forward_message()`, and
> `send_message()`. The SDK manages key resolution, encryption, and routing."

---

## Q&A Prepared Answers

**Q: Can the mediator read messages?**
> No. Messages are encrypted with the recipient's public key before being wrapped
> in a forward envelope. The mediator only sees routing metadata.

**Q: What happens if Bob is offline?**
> Messages queue on the mediator. When Bob reconnects, they're delivered via
> WebSocket live stream or REST fetch.

**Q: What DID method is used?**
> `did:peer` — a self-contained method that doesn't require a blockchain or
> registry. The DID document is derived from the DID string itself.

**Q: Can this work with other mediators?**
> Yes. DIDComm v2.1 is a standard protocol. Any compliant mediator will work.

**Q: How are keys managed?**
> The TDK's `setup_environment` tool generates keys and stores them in the
> `environments.json` file. In production, you'd use a proper secrets manager
> or hardware security module.
