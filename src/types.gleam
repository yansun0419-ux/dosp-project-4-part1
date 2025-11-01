// Core data types for Reddit Clone
import gleam/dict.{type Dict}
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

// Engine State
pub type EngineState {
  EngineState(
    users: Dict(UserId, User),
    subreddits: Dict(SubredditName, Subreddit),
    posts: Dict(PostId, Post),
    comments: Dict(CommentId, Comment),
    messages: Dict(MessageId, DirectMessage),
    next_post_id: Int,
    next_comment_id: Int,
    next_message_id: Int,
  )
}
