# Enforcing Callback Called Exactly Once (no_std, no_alloc, Embassy)

## Summary from Discussion

In a strict `no_std` + no-allocator Embassy environment with F# mailbox-style message passing:

### Core Pattern: `FnOnce` + `Option::take()` + Drop Guard

- **At most once**: Use `FnOnce` (consumed on call) + `Option::take()`.
- **Exactly once**: Drop impl calls the callback with a default error (e.g. `Reply::Err(CallbackError::Dropped)`) if not explicitly called.

### Recommended Implementation

```rust
use core::marker::PhantomData;

#[derive(Debug, PartialEq)]
pub enum Reply {
    Ok(/* success data */),
    Err(CallbackError),
}

#[derive(Debug, PartialEq)]
pub enum CallbackError {
    Dropped,  // Never invoked by processor
    // Timeout, Cancelled, etc.
}

pub struct GuaranteedCallback<CB>
where
    CB: FnOnce(Reply),
{
    inner: Option<CB>,
    _must_call: PhantomData<()>,
}

impl<CB: FnOnce(Reply)> GuaranteedCallback<CB> {
    pub fn new(cb: CB) -> Self {
        Self {
            inner: Some(cb),
            _must_call: PhantomData,
        }
    }

    /// Normal completion path
    pub fn call(mut self, reply: Reply) {
        if let Some(cb) = self.inner.take() {
            cb(reply);
        }
    }
}

impl<CB: FnOnce(Reply)> Drop for GuaranteedCallback<CB> {
    fn drop(&mut self) {
        if let Some(cb) = self.inner.take() {
            defmt::warn!("Callback dropped without explicit call — firing with error");
            cb(Reply::Err(CallbackError::Dropped));
        }
    }
}
```

### Usage in Message

```rust
pub struct Message<CB = fn(Reply)> {
    payload: u32,
    callback: Option<GuaranteedCallback<CB>>,
}

impl<CB: FnOnce(Reply)> Message<CB> {
    pub fn new(payload: u32, callback: CB) -> Self {
        Self {
            payload,
            callback: Some(GuaranteedCallback::new(callback)),
        }
    }

    pub fn complete(mut self, reply: Reply) {
        if let Some(cb) = self.callback.take() {
            cb.call(reply);
        }
    }
}
```

### Benefits
- Guaranteed invocation exactly once.
- Safe for async tasks.
- Zero allocation, fully static/generic.
- Works with F# interop (closures from F# side become Rust FnOnce).

### Alternatives
- If drop-on-error is undesirable: `panic!()` or `defmt::error!()` in Drop.
- For async callbacks: Similar guard around a future.

Store this pattern in your Embassy/RP2350 projects.
