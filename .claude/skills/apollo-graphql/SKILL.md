---
name: apollo-graphql
description: Best practices for writing GraphQL queries, mutations, and fragments with Apollo iOS. Use when creating or modifying GraphQL operations, setting up cache normalization, or working with fragments and type unions.
---

# Apollo GraphQL Best Practices

This skill defines our team's best practices for writing GraphQL operations with Apollo iOS.

## CRITICAL: Always Query ID/Key Fields

**This is the most important rule.** Any field that returns a type with an `id` or unique key field MUST include that field in the selection set.

### Why This Matters

Apollo uses normalized caching. When you query an object without its `id`, Apollo cannot:
- Properly normalize the cache entry
- Update existing cached data when the same object is returned elsewhere
- Maintain referential integrity across queries

**Failing to include `id` fields will corrupt the Apollo store and cause subtle, hard-to-debug data inconsistencies.**

### Required Pattern

```graphql
# CORRECT - Always include id fields
query GetUser {
  user {
    id  # REQUIRED - Never omit this
    name
    email
    profile {
      id  # REQUIRED - nested objects need ids too
      avatarUrl
    }
    posts {
      id  # REQUIRED - items in lists need ids
      title
    }
  }
}

# WRONG - Missing id fields will break cache normalization
query GetUser {
  user {
    name
    email
    profile {
      avatarUrl  # Missing id - cache corruption risk
    }
    posts {
      title  # Missing id - cache corruption risk
    }
  }
}
```

### Key Fields Beyond `id`

Some types use different fields as their cache key (configured via `SchemaConfiguration.cacheKeyInfo`). Always include whatever field(s) serve as the unique identifier:

```graphql
# If a type uses a composite key or different field name
query GetProduct {
  product {
    sku       # Primary key for this type
    storeId   # Part of composite key
    name
    price
  }
}
```

## Fragment Best Practices

### Use Fragments for Reusable Selections

Fragments enable component-based data requirements and reduce duplication:

```graphql
# Define reusable fragments
fragment UserBasicInfo on User {
  id  # Always include the id
  name
  avatarUrl
}

fragment UserContactInfo on User {
  id
  email
  phoneNumber
}

# Compose fragments in queries
query GetUserProfile {
  user {
    ...UserBasicInfo
    ...UserContactInfo
    createdAt
  }
}
```

### Fragment Colocation

Keep fragments close to the components/views that use them:
- Define fragments in the same file or module as the UI component
- Name fragments after the component: `ComponentName_TypeName`
- Let parent components compose child fragments

```graphql
# UserCard component's fragment
fragment UserCard_User on User {
  id
  name
  avatarUrl
}

# UserProfile component composes UserCard's fragment
fragment UserProfile_User on User {
  id
  ...UserCard_User
  bio
  followersCount
}
```

### Fragment Spread Merging

Apollo iOS automatically merges fragment fields from the same parent type into the parent selection. Access fields directly or via the `fragments` property:

```swift
// Both access patterns work when fragment is on same type
let name = data.user.name
let name = data.user.fragments.userBasicInfo.name
```

## Type Unions and Interfaces

### Always Include `__typename`

Apollo automatically includes `__typename`, but be aware it's essential for:
- Runtime type resolution
- Cache key computation
- Type-conditional rendering

### Handle All Possible Types

When querying union types or interfaces, handle all concrete types:

```graphql
query GetSearchResults {
  search(query: "test") {
    ... on User {
      id  # Required
      name
    }
    ... on Post {
      id  # Required
      title
      author {
        id  # Required - nested object
        name
      }
    }
    ... on Comment {
      id  # Required
      body
    }
  }
}
```

### Interface Fragments

When working with interfaces, define fragments on the interface for shared fields:

```graphql
fragment NodeFields on Node {
  id  # All Node implementers have id
}

fragment AnimalFields on Animal {
  id
  species
  # Type-specific fields via inline fragments
  ... on Dog {
    breed
    isGoodBoy
  }
  ... on Cat {
    breed
    livesRemaining
  }
}
```

## Cache Configuration

### SchemaConfiguration Setup

Configure cache key resolution in your generated `SchemaConfiguration`:

```swift
enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {
  static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? {
    // Default: use "id" field if present
    if let id = try? object["id"] as? String {
      return CacheKeyInfo(id: id)
    }

    // Custom key for specific types
    if type == Objects.Product {
      if let sku = try? object["sku"] as? String,
         let storeId = try? object["storeId"] as? String {
        return CacheKeyInfo(id: "\(sku):\(storeId)")
      }
    }

    // Interface-level grouping for shared cache keys
    if type.implements(Interfaces.Node) {
      return try? CacheKeyInfo(
        jsonValue: object["id"],
        uniqueKeyGroup: Interfaces.Node.name
      )
    }

    return nil
  }
}
```

### Cache Policies

Choose appropriate cache policies for your use case:

```swift
// Default: Return cache if available, otherwise fetch
client.fetch(query: query, cachePolicy: .returnCacheDataElseFetch)

// Always fetch fresh data
client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData)

// Cache only - fail if not cached
client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch)

// Return cache immediately, then fetch and update
client.fetch(query: query, cachePolicy: .returnCacheDataAndFetch)
```

## Query Design Guidelines

### 1. Request Only What You Need

```graphql
# GOOD - Minimal selection
query GetUserName {
  user {
    id
    name
  }
}

# AVOID - Over-fetching
query GetUser {
  user {
    id
    name
    email
    phone
    address
    preferences
    # ... 20 more fields you don't need
  }
}
```

### 2. Use Variables for Dynamic Values

```graphql
query GetUser($userId: ID!) {
  user(id: $userId) {
    id
    name
  }
}
```

### 3. Name All Operations

```graphql
# GOOD - Named operation
query GetUserProfile {
  user { id name }
}

# AVOID - Anonymous operation
query {
  user { id name }
}
```

### 4. Use Aliases for Field Conflicts

```graphql
query GetUsers {
  currentUser: user(id: "me") {
    id
    name
  }
  otherUser: user(id: "123") {
    id
    name
  }
}
```

## Mutations

### Include Sufficient Return Data

Return enough data to update the cache properly:

```graphql
mutation UpdateUser($input: UpdateUserInput!) {
  updateUser(input: $input) {
    id  # REQUIRED - for cache normalization
    name
    email
    # Return all fields that might have changed
    updatedAt
  }
}
```

### Optimistic Updates

For better UX, configure optimistic responses that include the id:

```swift
client.perform(mutation: mutation, optimisticResponse: [
  "__typename": "User",
  "id": userId,  // Required for cache update
  "name": newName
])
```

## Common Mistakes to Avoid

1. **Omitting `id` fields** - Causes cache corruption
2. **Not handling all union/interface types** - Runtime crashes
3. **Over-fetching data** - Performance impact
4. **Anonymous operations** - Poor debugging experience
5. **Hardcoding variables** - Inflexible queries
6. **Missing nested object ids** - Partial cache corruption

## Checklist for Every Query/Mutation

Before committing any GraphQL operation, verify:

- [ ] Every object type has its `id` (or key field) selected
- [ ] Nested objects include their `id` fields
- [ ] List items include `id` fields
- [ ] Union/interface types handle all possibilities
- [ ] Fragments include `id` on their type
- [ ] Operation has a descriptive name
- [ ] Only necessary fields are selected
