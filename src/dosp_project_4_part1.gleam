import engine
import gleam/erlang/process
import gleam/io
import gleam/string
import simulator.{SimulationConfig}

pub fn main() -> Nil {
  io.println("=== Reddit Clone - Distributed Systems Project ===")
  io.println("")
  
  // Start the Reddit engine
  io.println("Starting Reddit Engine...")
  let engine_result = engine.start()
  
  case engine_result {
    Ok(started) -> {
      io.println("Engine started successfully!")
      io.println("")
      
      // Configure simulation
      let config = SimulationConfig(
        num_clients: 100,           // Simulate 100 users
        num_subreddits: 20,         // Create 20 subreddits
        num_posts_per_user: 5,      // Each user makes ~5 actions
        zipf_param: 1.5,            // Zipf distribution parameter
        simulation_duration_ms: 5000, // 5 second simulation
      )
      
      // Run simulation
      let _stats = simulator.run_simulation(config, started.data)
      
      io.println("")
      io.println("=== Simulation Complete ===")
      
      // Shutdown engine
      io.println("Shutting down engine...")
      process.send(started.data, engine.Shutdown)
    }
    Error(err) -> {
      io.println("Failed to start engine: " <> string.inspect(err))
    }
  }
}
