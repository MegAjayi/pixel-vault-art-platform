;; pixel-vault.clar
;; A smart contract to manage digital artwork storage, sharing, and collaboration on the Stacks blockchain.
;; This contract serves as the central hub for all Pixel Vault operations, handling artwork registration, 
;; ownership management, collaboration permissions, and public/private visibility settings.

;; ===================
;; Constants & Errors
;; ===================
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-not-authorized (err u100))
(define-constant err-artwork-not-found (err u101))
(define-constant err-invalid-parameters (err u102))
(define-constant err-artwork-already-exists (err u103))
(define-constant err-not-artwork-owner (err u104))
(define-constant err-not-collaborator (err u105))
(define-constant err-invalid-visibility (err u106))
(define-constant err-version-not-found (err u107))
(define-constant err-max-collaborators-reached (err u108))
(define-constant err-already-collaborator (err u109))
(define-constant err-reaction-already-exists (err u110))

;; Other constants
(define-constant max-collaborators u10)
(define-constant public-visibility "public")
(define-constant private-visibility "private")
(define-constant collaborative-visibility "collaborative")

;; ===================
;; Data Maps
;; ===================

;; Stores the main artwork metadata
(define-map artworks 
  { artwork-id: uint } 
  {
    owner: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    created-at: uint,
    latest-version-id: uint,
    visibility: (string-ascii 20),
    collaborators: (list 10 principal),
    total-reactions: uint
  }
)

;; Stores the version history of each artwork
(define-map artwork-versions
  { artwork-id: uint, version-id: uint }
  {
    contributor: principal,
    metadata-uri: (string-ascii 256),
    timestamp: uint,
    change-description: (string-utf8 200)
  }
)

;; Stores user reactions to artworks
(define-map artwork-reactions
  { artwork-id: uint, user: principal }
  {
    reaction-type: (string-ascii 20),
    timestamp: uint
  }
)

;; Stores comments on artworks
(define-map artwork-comments
  { artwork-id: uint, comment-id: uint }
  {
    user: principal,
    content: (string-utf8 500),
    timestamp: uint
  }
)

;; Counter for artwork IDs
(define-data-var next-artwork-id uint u1)

;; Counter for comment IDs - per artwork
(define-map next-comment-id { artwork-id: uint } uint)

;; ===================
;; Private Functions
;; ===================

;; Check if principal is the artwork owner
(define-private (is-artwork-owner (artwork-id uint) (user principal))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork (is-eq (get owner artwork) user)
    false
  )
)

;; Check if principal is a collaborator on the artwork
(define-private (is-collaborator (artwork-id uint) (user principal))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork (includes (get collaborators artwork) user)
    false
  )
)

;; Check if principal can modify the artwork (owner or collaborator)
(define-private (can-modify-artwork (artwork-id uint) (user principal))
  (or
    (is-artwork-owner artwork-id user)
    (is-collaborator artwork-id user)
  )
)

;; Helper to check if a list includes a principal
(define-private (includes (lst (list 10 principal)) (value principal))
  (match (index-of lst value)
    index true
    false
  )
)

;; Get next comment ID for an artwork
(define-private (get-next-comment-id (artwork-id uint))
  (match (map-get? next-comment-id { artwork-id: artwork-id })
    current-id (+ current-id u1)
    u1
  )
)

;; ===================
;; Read-only Functions
;; ===================

;; Get artwork details
(define-read-only (get-artwork (artwork-id uint))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork (ok artwork)
    err-artwork-not-found
  )
)

;; Get a specific version of an artwork
(define-read-only (get-artwork-version (artwork-id uint) (version-id uint))
  (match (map-get? artwork-versions { artwork-id: artwork-id, version-id: version-id })
    version (ok version)
    err-version-not-found
  )
)

;; Check if caller can view this artwork
(define-read-only (can-view-artwork (artwork-id uint))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork 
    (or 
      (is-eq (get visibility artwork) public-visibility)
      (is-eq (get visibility artwork) collaborative-visibility)
      (is-artwork-owner artwork-id tx-sender)
      (is-collaborator artwork-id tx-sender)
    )
    false
  )
)

;; Get all versions of an artwork
(define-read-only (get-all-artwork-versions (artwork-id uint))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork 
    (if (can-view-artwork artwork-id)
      (ok (get latest-version-id artwork))
      err-not-authorized
    )
    err-artwork-not-found
  )
)

;; Get total reaction count for an artwork
(define-read-only (get-artwork-reaction-count (artwork-id uint))
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork (ok (get total-reactions artwork))
    err-artwork-not-found
  )
)

;; ===================
;; Public Functions
;; ===================

;; Register a new artwork
(define-public (register-artwork 
  (title (string-ascii 100))
  (description (string-utf8 500))
  (metadata-uri (string-ascii 256))
  (visibility (string-ascii 20)))
  (let
    (
      (artwork-id (var-get next-artwork-id))
      (timestamp (unwrap! (get-block-info? time (- block-height u1)) err-invalid-parameters))
    )
    ;; Validate visibility setting
    (asserts! 
      (or 
        (is-eq visibility public-visibility) 
        (is-eq visibility private-visibility) 
        (is-eq visibility collaborative-visibility)
      ) 
      err-invalid-visibility
    )
    
    ;; Create the artwork entry
    (map-set artworks
      { artwork-id: artwork-id }
      {
        owner: tx-sender,
        title: title,
        description: description,
        created-at: timestamp,
        latest-version-id: u1,
        visibility: visibility,
        collaborators: (list),
        total-reactions: u0
      }
    )
    
    ;; Create the initial version
    (map-set artwork-versions
      { artwork-id: artwork-id, version-id: u1 }
      {
        contributor: tx-sender,
        metadata-uri: metadata-uri,
        timestamp: timestamp,
        change-description: "Initial version"
      }
    )
    
    ;; Initialize comment counter for this artwork
    (map-set next-comment-id { artwork-id: artwork-id } u1)
    
    ;; Increment the artwork ID counter
    (var-set next-artwork-id (+ artwork-id u1))
    
    (ok artwork-id)
  )
)

;; Add a new version to an existing artwork
(define-public (add-artwork-version 
  (artwork-id uint)
  (metadata-uri (string-ascii 256))
  (change-description (string-utf8 200)))
  (let
    (
      (timestamp (unwrap! (get-block-info? time (- block-height u1)) err-invalid-parameters))
    )
    ;; Check if artwork exists and user can modify it
    (asserts! (can-modify-artwork artwork-id tx-sender) err-not-authorized)
    
    ;; Get the current artwork data
    (match (map-get? artworks { artwork-id: artwork-id })
      artwork
      (let
        (
          (next-version-id (+ (get latest-version-id artwork) u1))
        )
        ;; Add the new version
        (map-set artwork-versions
          { artwork-id: artwork-id, version-id: next-version-id }
          {
            contributor: tx-sender,
            metadata-uri: metadata-uri,
            timestamp: timestamp,
            change-description: change-description
          }
        )
        
        ;; Update the latest version reference
        (map-set artworks
          { artwork-id: artwork-id }
          (merge artwork { latest-version-id: next-version-id })
        )
        
        (ok next-version-id)
      )
      err-artwork-not-found
    )
  )
)

;; Update artwork visibility
(define-public (update-artwork-visibility (artwork-id uint) (visibility (string-ascii 20)))
  ;; Verify the caller is the artwork owner (only owner can change visibility)
  (asserts! (is-artwork-owner artwork-id tx-sender) err-not-artwork-owner)
  
  ;; Validate visibility setting
  (asserts! 
    (or 
      (is-eq visibility public-visibility) 
      (is-eq visibility private-visibility) 
      (is-eq visibility collaborative-visibility)
    ) 
    err-invalid-visibility
  )
  
  ;; Update the artwork visibility
  (match (map-get? artworks { artwork-id: artwork-id })
    artwork
    (begin
      (map-set artworks
        { artwork-id: artwork-id }
        (merge artwork { visibility: visibility })
      )
      (ok true)
    )
    err-artwork-not-found
  )
)

;; Add a collaborator to an artwork
(define-public (add-collaborator (artwork-id uint) (collaborator principal))
  (let
    (
      (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) err-artwork-not-found))
    )
    ;; Check if caller is the artwork owner
    (asserts! (is-artwork-owner artwork-id tx-sender) err-not-artwork-owner)
    
    ;; Check if collaborator is already added
    (asserts! (not (includes (get collaborators artwork) collaborator)) err-already-collaborator)
    
    ;; Check if maximum collaborators reached
    (asserts! (< (len (get collaborators artwork)) max-collaborators) err-max-collaborators-reached)
    
    ;; Add the collaborator
    (map-set artworks
      { artwork-id: artwork-id }
      (merge artwork { 
        collaborators: (append (get collaborators artwork) collaborator)
      })
    )
    
    (ok true)
  )
)

;; Remove a collaborator from an artwork
(define-public (remove-collaborator (artwork-id uint) (collaborator principal))
  (let
    (
      (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) err-artwork-not-found))
    )
    ;; Check if caller is the artwork owner
    (asserts! (is-artwork-owner artwork-id tx-sender) err-not-artwork-owner)
    
    ;; Filter out the collaborator
    (map-set artworks
      { artwork-id: artwork-id }
      (merge artwork { 
        collaborators: (filter (lambda (p) (not (is-eq p collaborator))) (get collaborators artwork))
      })
    )
    
    (ok true)
  )
)

;; Add a reaction to an artwork
(define-public (add-reaction (artwork-id uint) (reaction-type (string-ascii 20)))
  (let
    (
      (timestamp (unwrap! (get-block-info? time (- block-height u1)) err-invalid-parameters))
      (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) err-artwork-not-found))
    )
    ;; Check if artwork is viewable by the user
    (asserts! (can-view-artwork artwork-id) err-not-authorized)
    
    ;; Check if user already reacted
    (asserts! (is-none (map-get? artwork-reactions { artwork-id: artwork-id, user: tx-sender })) err-reaction-already-exists)
    
    ;; Add the reaction
    (map-set artwork-reactions
      { artwork-id: artwork-id, user: tx-sender }
      {
        reaction-type: reaction-type,
        timestamp: timestamp
      }
    )
    
    ;; Update total reaction count
    (map-set artworks
      { artwork-id: artwork-id }
      (merge artwork { total-reactions: (+ (get total-reactions artwork) u1) })
    )
    
    (ok true)
  )
)

;; Add a comment to an artwork
(define-public (add-comment (artwork-id uint) (content (string-utf8 500)))
  (let
    (
      (timestamp (unwrap! (get-block-info? time (- block-height u1)) err-invalid-parameters))
      (comment-id (get-next-comment-id artwork-id))
    )
    ;; Check if artwork exists and is viewable
    (asserts! (can-view-artwork artwork-id) err-not-authorized)
    
    ;; Add the comment
    (map-set artwork-comments
      { artwork-id: artwork-id, comment-id: comment-id }
      {
        user: tx-sender,
        content: content,
        timestamp: timestamp
      }
    )
    
    ;; Update the comment counter
    (map-set next-comment-id { artwork-id: artwork-id } comment-id)
    
    (ok comment-id)
  )
)

;; Transfer artwork ownership
(define-public (transfer-artwork (artwork-id uint) (new-owner principal))
  (let
    (
      (artwork (unwrap! (map-get? artworks { artwork-id: artwork-id }) err-artwork-not-found))
    )
    ;; Check if caller is the artwork owner
    (asserts! (is-artwork-owner artwork-id tx-sender) err-not-artwork-owner)
    
    ;; Transfer ownership
    (map-set artworks
      { artwork-id: artwork-id }
      (merge artwork { owner: new-owner })
    )
    
    (ok true)
  )
)