import gleam/io
import gleam/string
import registry
import simulator.{SimulationConfig}

pub fn main() -> Nil {
  io.println("=== Reddit Clone - Distributed Systems Project ===")
  io.println("=== Multi-Actor Distributed Architecture ===")
  io.println("")

  // Start the Registry (注册中心)
  io.println("Starting Registry Actor...")
  let registry_result = registry.start()

  case registry_result {
    Ok(started) -> {
      io.println("Registry started successfully!")
      io.println("Ready to spawn Subreddit Actors...")
      io.println("")

      // Configure simulation for MASSIVE scale
      let config =
        SimulationConfig(
          num_clients: 10_000,
          // Simulate 10,000 concurrent users
          num_subreddits: 100,
          // Create 100 subreddits (100 independent Actors!)
          num_posts_per_user: 100,
          // Each user makes 100 actions
          zipf_param: 1.5,
          // Zipf distribution parameter
          simulation_duration_ms: 60_000,
          // 60 second simulation
        )

      io.println("⚡ HIGH-PERFORMANCE MODE ⚡")
      io.println("Users: 10,000 | Subreddits: 100 | Actions: 1,000,000")
      io.println("This will generate approximately 1 MILLION operations!")
      io.println("")

      // Run simulation with distributed architecture
      let _stats = simulator.run_simulation(config, started.data)

      io.println("")
      io.println("=== Simulation Complete ===")
      io.println(
        "Note: This is a TRUE distributed system with multiple concurrent Actors!",
      )
    }
    Error(err) -> {
      io.println("Failed to start registry: " <> string.inspect(err))
    }
  }
}
