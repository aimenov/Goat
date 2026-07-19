/// Presentation pacing constants for the client-side event queue in
/// `game_controller.dart`. Server batches land in one frame; these gaps give
/// each moment (trick resolution, deal summary, game over) room to register.
library;

/// Hold a completed trick on the table before it vacuums away.
const beatHoldMs = 700;

/// Breath after a trick resolves before the next action appears.
const postTrickMs = 900;

/// Pause between a deal's summary (dealEnded) and the next deal-out.
const dealTransitionMs = 3000;

/// Delay before the game-over screen so the final deal summary is seen.
const gameOverMs = 2000;

/// Ceiling on accumulated presentation lag behind the live server state.
const maxQueueLagMs = 5000;
