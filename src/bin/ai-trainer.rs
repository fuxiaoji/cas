//! Native-only genetic trainer for the CAS surface AI.
//!
//! The trainer is deterministic and writes `data/ai/evolved.json`, which the
//! engine embeds at build time. It never fabricates fitness: every score in the
//! report comes from a headless match on the same Rust core as the game.

fn main() {
    if let Err(error) = cas_core::ai_evolve::run_cli() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
