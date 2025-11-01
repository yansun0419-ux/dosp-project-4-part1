// Core data types for Reddit Clone
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

// User ID type
pub type UserId =
  String

// Subreddit name type
pub type SubredditName =
  String

// Post ID type
pub type PostId =
  String

// Comment ID type
pub type CommentId =
  String

// Direct Message ID type
pub type MessageId =
  String

// User account
pub type User {
  User(
    id: UserId,
    username: String,
    karma: Int,
    subscribed_subreddits: List(SubredditName),
    is_online: Bool,
  )
}

// Subreddit
pub type Subreddit {
  Subreddit(
    name: SubredditName,
    creator: UserId,
    members: List(UserId),
    posts: List(PostId),
    created_at: Int,
  )
}

// Post
pub type Post {
  Post(
    id: PostId,
    author: UserId,
    subreddit: SubredditName,
    title: String,
    content: String,
    upvotes: Int,
    downvotes: Int,
    comments: List(CommentId),
    created_at: Int,
  )
}

// Comment (hierarchical structure)
pub type Comment {
  Comment(
    id: CommentId,
    author: UserId,
    post_id: PostId,
    parent_comment_id: Option(CommentId),
    content: String,
    upvotes: Int,
    downvotes: Int,
    replies: List(CommentId),
    created_at: Int,
  )
}

// Direct Message
pub type DirectMessage {
  DirectMessage(
    id: MessageId,
    from: UserId,
    to: UserId,
    content: String,
    read: Bool,
    created_at: Int,
  )
}

// Registry State - Central registry for managing users and subreddit routing
pub type RegistryState {
  RegistryState(
    users: Dict(UserId, User),
    subreddit_actors: Dict(SubredditName, SubredditActorRef),
    messages: Dict(MessageId, DirectMessage),
    next_message_id: Int,
  )
}

// Subreddit Actor Reference - Points to a specific subreddit actor
pub type SubredditActorRef {
  SubredditActorRef(name: SubredditName, subject: Subject(SubredditMessage))
}

// Subreddit Actor State - Each subreddit has one instance
pub type SubredditState {
  SubredditState(
    name: SubredditName,
    creator: UserId,
    members: List(UserId),
    posts: Dict(PostId, Post),
    comments: Dict(CommentId, Comment),
    next_post_id: Int,
    next_comment_id: Int,
    created_at: Int,
  )
}

// ========== Distributed Message Types ==========

// Registry Actor Messages - Global operations handled by the central registry
pub type RegistryMessage {
  // User operations
  RegisterUser(username: String, reply: Subject(Result(UserId, String)))
  GetUser(user_id: UserId, reply: Subject(Result(User, String)))
  SetUserOnline(
    user_id: UserId,
    is_online: Bool,
    reply: Subject(Result(Nil, String)),
  )

  // Subreddit management
  CreateSubreddit(
    name: SubredditName,
    creator: UserId,
    reply: Subject(Result(Subject(SubredditMessage), String)),
  )
  GetSubredditActor(
    name: SubredditName,
    reply: Subject(Result(Subject(SubredditMessage), String)),
  )

  // Direct message operations (global)
  SendDirectMessage(
    from: UserId,
    to: UserId,
    content: String,
    reply: Subject(Result(MessageId, String)),
  )
  GetDirectMessages(
    user_id: UserId,
    reply: Subject(Result(List(DirectMessage), String)),
  )
  ReplyToDirectMessage(
    message_id: MessageId,
    from: UserId,
    content: String,
    reply: Subject(Result(MessageId, String)),
  )

  // Statistics
  GetRegistryStats(reply: Subject(RegistryStats))
}

// Subreddit Actor Messages - Operations within a specific subreddit
pub type SubredditMessage {
  // Member management
  JoinSubreddit(user_id: UserId, reply: Subject(Result(Nil, String)))
  LeaveSubreddit(user_id: UserId, reply: Subject(Result(Nil, String)))
  GetSubredditInfo(reply: Subject(Result(Subreddit, String)))

  // Post operations
  CreatePost(
    author: UserId,
    title: String,
    content: String,
    reply: Subject(Result(PostId, String)),
  )
  GetPost(post_id: PostId, reply: Subject(Result(Post, String)))
  VotePost(
    post_id: PostId,
    user_id: UserId,
    is_upvote: Bool,
    reply: Subject(Result(Nil, String)),
  )
  GetFeed(user_id: UserId, reply: Subject(Result(List(Post), String)))

  // Comment operations
  CreateComment(
    author: UserId,
    post_id: PostId,
    parent_comment_id: Option(CommentId),
    content: String,
    reply: Subject(Result(CommentId, String)),
  )
  GetComment(comment_id: CommentId, reply: Subject(Result(Comment, String)))
  VoteComment(
    comment_id: CommentId,
    user_id: UserId,
    is_upvote: Bool,
    reply: Subject(Result(Nil, String)),
  )
  GetPostComments(
    post_id: PostId,
    reply: Subject(Result(List(Comment), String)),
  )

  // Statistics
  GetSubredditStats(reply: Subject(SubredditStats))
}

// Statistics Types
pub type RegistryStats {
  RegistryStats(
    total_users: Int,
    online_users: Int,
    total_subreddits: Int,
    total_messages: Int,
  )
}

pub type SubredditStats {
  SubredditStats(
    name: SubredditName,
    total_members: Int,
    total_posts: Int,
    total_comments: Int,
  )
}
