/// The log bounds of `openspec/architecture.md` (Resource Bounds) and design
/// D6. Every number here is a documented limit; tests use the same values.
library;

/// Lines kept in memory per source.
const ringMaxLines = 10000;

/// Bytes kept in memory per source.
const ringMaxBytes = 4 * 1024 * 1024;

/// Lines a `Backlog` request can return.
const backlogMaxLines = 5000;

/// A longer line is cut here and delivered with `truncated: true`.
const maxLineBytes = 64 * 1024;

/// A follower further behind than this many lines gets a `dropped` marker.
const followMaxLagLines = 1000;

/// A follower further behind than this many bytes gets a `dropped` marker.
const followMaxLagBytes = 4 * 1024 * 1024;

/// Source events (`file_switched`, `waiting`, `error`) a paused follower
/// queues; the oldest are dropped beyond it.
const followMaxEvents = 100;

/// A `LogBatch` is closed once its lines would take this many bytes on the
/// wire. A line is counted at three times its size on disk, the most a
/// decoder can expand it (an invalid UTF-8 byte becomes a three-byte U+FFFD),
/// so a batch stays far below the 16 MiB message limit.
const followBatchBytes = 4 * 1024 * 1024;

/// Size of one stdout capture file before it rotates.
const captureFileBytes = 10 * 1024 * 1024;

/// Capture files kept per instance.
const captureFileCount = 5;

/// Bytes of the file head hashed for the current-run mark (design D6).
const markHashBytes = 4096;

/// How far back from a saved offset (or the end of a file seen for the first
/// time) a tailer reads to refill the ring: the ring's byte bound.
const historyWindowBytes = ringMaxBytes;
