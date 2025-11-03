import gleam/io
import gleam/string
import registry
import simulator.{SimulationConfig}

pub fn main() -> Nil {
  io.println("=== Reddit Clone - Distributed Systems Project ===")
  io.println("=== Multi-Actor Distributed Architecture ===")
  io.println("")

  // Start the Registry (central coordinator)
  io.println("Starting Registry Actor...")
  let registry_result = registry.start()

  case registry_result {
    Ok(started) -> {
      io.println("Registry started successfully!")
      io.println("Ready to spawn Subreddit Actors...")
      io.println("")

      // Configure simulation for distributed testing
      // Note: Actors run concurrently, but each action is processed sequentially
      let config =
        SimulationConfig(
          num_clients: 100,
          // 100 concurrent client actors
          num_subreddits: 20,
          // 20 subreddit actors (fully distributed)
          num_posts_per_user: 300,
          // Each client performs 300 actions
          zipf_param: 1.5,
          // Zipf distribution parameter (realistic social media pattern)
          simulation_duration_ms: 30_000,
          // 30 second simulation window
          progress_update_interval: 1000,
          // Update progress every 1 second
        )

      io.println("DISTRIBUTED ACTOR SYSTEM")
      io.println("Clients: 100 | Subreddit Actors: 20 | Total Actions: 5,000")
      io.println("Architecture: Registry + Multiple Subreddit Actors")
      io.println("")

      // Run simulation with distributed architecture
      let _stats = simulator.run_simulation(config, started.data)

      io.println("")
      io.println("=== Simulation Complete ===")
    }
    Error(err) -> {
      io.println("Failed to start registry: " <> string.inspect(err))
    }
  }
}
