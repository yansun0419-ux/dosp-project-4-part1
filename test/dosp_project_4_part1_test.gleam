import engine
import gleam/erlang/process
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

// Test engine startup
pub fn engine_start_test() {
  let result = engine.start()
  should.be_ok(result)

  case result {
    Ok(started) -> {
      process.send(started.data, engine.Shutdown)
    }
    Error(_) -> Nil
  }
}

// Test user registration
pub fn user_registration_test() {
  let assert Ok(started) = engine.start()
  let engine_actor = started.data

  let reply = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "testuser", reply: reply),
  )

  let result = process.receive(reply, 1000)
  let _assert = should.be_ok(result)

  case result {
    Ok(user_result) -> {
      let _assert2 = should.be_ok(user_result)
      Nil
    }
    Error(_) -> Nil
  }

  process.send(engine_actor, engine.Shutdown)
}

// Test subreddit creation
pub fn subreddit_creation_test() {
  let assert Ok(started) = engine.start()
  let engine_actor = started.data

  // Register a user first
  let register_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "creator", reply: register_reply),
  )
  let assert Ok(Ok(user_id)) = process.receive(register_reply, 1000)

  // Create subreddit
  let sub_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.CreateSubreddit(name: "test_sub", creator: user_id, reply: sub_reply),
  )

  let result = process.receive(sub_reply, 1000)
  let _assert = should.be_ok(result)

  case result {
    Ok(sub_result) -> {
      let _assert2 = should.be_ok(sub_result)
      Nil
    }
    Error(_) -> Nil
  }

  process.send(engine_actor, engine.Shutdown)
}

// Test post creation
pub fn post_creation_test() {
  let assert Ok(started) = engine.start()
  let engine_actor = started.data

  // Register user
  let register_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "poster", reply: register_reply),
  )
  let assert Ok(Ok(user_id)) = process.receive(register_reply, 1000)

  // Create subreddit
  let sub_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.CreateSubreddit(name: "test_sub", creator: user_id, reply: sub_reply),
  )
  let assert Ok(Ok(_)) = process.receive(sub_reply, 1000)

  // Create post
  let post_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.CreatePost(
      author: user_id,
      subreddit: "test_sub",
      title: "Test Post",
      content: "This is a test",
      reply: post_reply,
    ),
  )

  let result = process.receive(post_reply, 1000)
  let _assert = should.be_ok(result)

  case result {
    Ok(post_result) -> {
      let _assert2 = should.be_ok(post_result)
      Nil
    }
    Error(_) -> Nil
  }

  process.send(engine_actor, engine.Shutdown)
}

// Test voting
pub fn voting_test() {
  let assert Ok(started) = engine.start()
  let engine_actor = started.data

  // Register user
  let register_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "voter", reply: register_reply),
  )
  let assert Ok(Ok(user_id)) = process.receive(register_reply, 1000)

  // Create subreddit and post
  let sub_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.CreateSubreddit(name: "test_sub", creator: user_id, reply: sub_reply),
  )
  let assert Ok(Ok(_)) = process.receive(sub_reply, 1000)

  let post_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.CreatePost(
      author: user_id,
      subreddit: "test_sub",
      title: "Vote Test",
      content: "Test voting",
      reply: post_reply,
    ),
  )
  let assert Ok(Ok(post_id)) = process.receive(post_reply, 1000)

  // Upvote the post
  let vote_reply = process.new_subject()
  process.send(
    engine_actor,
    engine.VotePost(
      post_id: post_id,
      user_id: user_id,
      is_upvote: True,
      reply: vote_reply,
    ),
  )

  let result = process.receive(vote_reply, 1000)
  let _assert = should.be_ok(result)

  process.send(engine_actor, engine.Shutdown)
}

// Test getting engine stats
pub fn engine_stats_test() {
  let assert Ok(started) = engine.start()
  let engine_actor = started.data

  // Register a few users
  let register_reply1 = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "user1", reply: register_reply1),
  )
  let assert Ok(Ok(_)) = process.receive(register_reply1, 1000)

  let register_reply2 = process.new_subject()
  process.send(
    engine_actor,
    engine.RegisterUser(username: "user2", reply: register_reply2),
  )
  let assert Ok(Ok(_)) = process.receive(register_reply2, 1000)

  // Get stats
  let stats_reply = process.new_subject()
  process.send(engine_actor, engine.GetStats(reply: stats_reply))

  let result = process.receive(stats_reply, 1000)
  should.be_ok(result)

  case result {
    Ok(stats) -> {
      should.be_true(stats.total_users >= 2)
      should.be_true(stats.online_users >= 2)
    }
    Error(_) -> Nil
  }

  process.send(engine_actor, engine.Shutdown)
}
