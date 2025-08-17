module coral_contract::core {
    use sui::event;
    use sui::clock::Clock;
    use sui::table::{Self, Table};
    use std::string::{Self, String};

    // ===== Error codes =====
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_SESSION_PUBKEY: u64 = 2;
    const E_INVALID_NOSTR_PUBKEY: u64 = 3;
    const E_INVALID_NICKNAME_LENGTH: u64 = 4;
    const E_INVALID_BIO_LENGTH: u64 = 5;
    const E_INVALID_MEMBERSHIP_TIER: u64 = 6;

    // ===== Constants =====
    const SESSION_VALIDITY_DURATION: u64 = 2592000000; // 30 days in milliseconds
    const MAX_NICKNAME_LENGTH: u64 = 50;
    const MAX_BIO_LENGTH: u64 = 500;
    const NOSTR_PUBKEY_LENGTH: u64 = 32; // 256 bits
    const SESSION_PUBKEY_LENGTH: u64 = 32; // 256 bits

    // ===== Membership Tiers =====
    const MEMBERSHIP_FREE: u8 = 0;
    const MEMBERSHIP_PREMIUM: u8 = 1;

    // ===== Structs =====
    public struct UserProfile has key, store {
        id: UID,
        owner: address,  // JWT에서 파생된 zklogin 주소
        nickname: String,
        bio: String,
        picture_url: Option<String>,
        picture_nft_id: Option<ID>,
        membership_tier: u8,
        is_verified: bool,
        created_at: u64,
        updated_at: u64,
        // Nostr 설정
        nostr_pubkey: vector<u8>,
    }

    public struct SessionRegistry has key {
        id: UID,
        owner: address,
        sessions: Table<vector<u8>, SessionData>,  // session id -> session data
        session_counter: u64,
    }

    public struct SessionData has store, drop {
        session_pubkey: vector<u8>,
        created_at: u64,
        expires_at: u64,
    }

    public struct ProfilePictureNFT has key {
        id: UID,
        owner: address,
        image_url: String, // Walrus URL
        name: String,
        description: String,
        artist: Option<String>,
        created_at: u64,
    }

    public struct AdminCap has key {
        id: UID,
        issuer: address,
    }

    // ===== Events =====
    public struct UserRegistered has copy, drop {
        user_address: address,
        profile_id: ID,
        nickname: String,
        timestamp: u64,
    }

    public struct ProfileUpdated has copy, drop {
        user_address: address,
        profile_id: ID,
        field: String,
        timestamp: u64,
    }

    public struct SessionCreated has copy, drop {
        user_address: address,
        session_pubkey: vector<u8>,
        expires_at: u64,
    }

    public struct SessionRevoked has copy, drop {
        user_address: address,
        session_pubkey: vector<u8>,
        timestamp: u64,
    }

    public struct VerificationStatusChanged has copy, drop {
        user_address: address,
        profile_id: ID,
        is_verified: bool,
        verified_by: address,
        timestamp: u64,
    }

    public struct MembershipChanged has copy, drop {
        user_address: address,
        profile_id: ID,
        old_tier: u8,
        new_tier: u8,
        timestamp: u64,
    }

    public struct ProfilePictureNFTMinted has copy, drop {
        owner: address,
        nft_id: ID,
        image_url: String,
        timestamp: u64,
    }

    // ===== Initialize Function =====
    fun init(ctx: &mut TxContext) {
        // Create initial admin capability for deployer
        let admin_cap = AdminCap {
            id: object::new(ctx),
            issuer: ctx.sender(),
        };

        transfer::transfer(admin_cap, ctx.sender());
    }

    // ===== User Registration and Profile Management =====
    entry fun create_user_profile(
        nickname: String,
        bio: String,
        nostr_pubkey: vector<u8>,
        session_pubkey: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();
        let current_time = clock.timestamp_ms();

        assert!(string::length(&nickname) > 0 && string::length(&nickname) <= MAX_NICKNAME_LENGTH, E_INVALID_NICKNAME_LENGTH);
        assert!(string::length(&bio) <= MAX_BIO_LENGTH, E_INVALID_BIO_LENGTH);
        assert!(vector::length(&nostr_pubkey) == NOSTR_PUBKEY_LENGTH, E_INVALID_NOSTR_PUBKEY);
        assert!(vector::length(&session_pubkey) == SESSION_PUBKEY_LENGTH, E_INVALID_SESSION_PUBKEY);

        let profile = UserProfile {
            id: object::new(ctx),
            owner: sender,
            nickname,
            bio,
            picture_url: option::none(),
            picture_nft_id: option::none(),
            membership_tier: MEMBERSHIP_FREE,
            is_verified: false,
            created_at: current_time,
            updated_at: current_time,
            nostr_pubkey,
        };

        let mut session_registry = SessionRegistry {
            id: object::new(ctx),
            owner: sender,
            sessions: table::new(ctx),
            session_counter: 0,
        };
        create_session(&mut session_registry, session_pubkey, clock, ctx);
        
        event::emit(UserRegistered {
            user_address: sender,
            profile_id: object::id(&profile),
            nickname: profile.nickname,
            timestamp: current_time,
        });

        transfer::transfer(profile, sender);
        transfer::transfer(session_registry, sender);
    }

    entry fun update_nickname(
        profile: &mut UserProfile,
        new_nickname: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(profile.owner == ctx.sender(), E_NOT_AUTHORIZED);
        assert!(string::length(&new_nickname) > 0 && string::length(&new_nickname) <= MAX_NICKNAME_LENGTH, E_INVALID_NICKNAME_LENGTH);

        profile.nickname = new_nickname;
        profile.updated_at = clock.timestamp_ms();

        event::emit(ProfileUpdated {
            user_address: profile.owner,
            profile_id: object::id(profile),
            field: string::utf8(b"nickname"),
            timestamp: profile.updated_at,
        });
    }

    entry fun update_bio(
        profile: &mut UserProfile,
        new_bio: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(profile.owner == ctx.sender(), E_NOT_AUTHORIZED);
        assert!(string::length(&new_bio) <= MAX_BIO_LENGTH, E_INVALID_BIO_LENGTH);

        profile.bio = new_bio;
        profile.updated_at = clock.timestamp_ms();

        event::emit(ProfileUpdated {
            user_address: profile.owner,
            profile_id: object::id(profile),
            field: string::utf8(b"bio"),
            timestamp: profile.updated_at,
        });
    }

    entry fun set_picture_url(
        profile: &mut UserProfile,
        picture_url: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(profile.owner == ctx.sender(), E_NOT_AUTHORIZED);

        profile.picture_url = option::some(picture_url);
        profile.picture_nft_id = option::none(); // Clear NFT if URL is set
        profile.updated_at = clock.timestamp_ms();

        event::emit(ProfileUpdated {
            user_address: profile.owner,
            profile_id: object::id(profile),
            field: string::utf8(b"picture_url"),
            timestamp: profile.updated_at,
        });
    }

    entry fun create_profile_picture_nft(
        profile: &mut UserProfile,
        image_url: String,
        name: String,
        description: String,
        artist: Option<String>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(profile.owner == ctx.sender(), E_NOT_AUTHORIZED);

        let current_time = clock.timestamp_ms();

        let nft = ProfilePictureNFT {
            id: object::new(ctx),
            owner: profile.owner,
            image_url,
            name,
            description,
            artist,
            created_at: current_time,
        };

        let nft_id = object::id(&nft);
        profile.picture_nft_id = option::some(nft_id);
        profile.picture_url = option::none(); // Clear URL if NFT is set
        profile.updated_at = current_time;

        event::emit(ProfileUpdated {
            user_address: profile.owner,
            profile_id: object::id(profile),
            field: string::utf8(b"picture_nft"),
            timestamp: current_time,
        });

        event::emit(ProfilePictureNFTMinted {
            owner: profile.owner,
            nft_id,
            image_url: nft.image_url,
            timestamp: current_time,
        });

        transfer::transfer(nft, profile.owner);
    }

    // ===== Session Management =====
    entry fun create_session(
        session_registry: &mut SessionRegistry,
        session_pubkey: vector<u8>,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(session_registry.owner == ctx.sender(), E_NOT_AUTHORIZED);

        let current_time = clock.timestamp_ms();
        let expires_at = current_time + SESSION_VALIDITY_DURATION;

        let session_data = SessionData {
            session_pubkey,
            created_at: current_time,
            expires_at,
        };

        table::add(&mut session_registry.sessions, session_pubkey, session_data);
        session_registry.session_counter = session_registry.session_counter + 1;

        event::emit(SessionCreated {
            user_address: session_registry.owner,
            session_pubkey,
            expires_at,
        });
    }

    /// read-only, 상태 변화 없음
    public fun validate_session(
        session_registry: &SessionRegistry,
        session_pubkey: vector<u8>,
        clock: &Clock,
    ): bool {
        if (!table::contains(&session_registry.sessions, session_pubkey)) {
            return false
        };
        
        let session_data = table::borrow(&session_registry.sessions, session_pubkey);
        let current_time = clock.timestamp_ms();
        current_time <= session_data.expires_at
    }

    entry fun revoke_session(
        session_registry: &mut SessionRegistry,
        session_pubkey: vector<u8>,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(session_registry.owner == ctx.sender(), E_NOT_AUTHORIZED);
        
        if (table::contains(&session_registry.sessions, session_pubkey)) {
            let _ = table::remove(&mut session_registry.sessions, session_pubkey);

            event::emit(SessionRevoked {
                user_address: session_registry.owner,
                session_pubkey,
                timestamp: clock.timestamp_ms(),
            });
        };
    }

    /// Todo: 만료된 세션 정리 더 효율적으로 하기
    entry fun cleanup_expired_sessions(
        session_registry: &mut SessionRegistry,
        expired_keys: vector<vector<u8>>,
        clock: &Clock,
    ) {
        let current_time = clock.timestamp_ms();
        let mut i = 0;
        let len = vector::length(&expired_keys);
        
        while (i < len) {
            let key = vector::borrow(&expired_keys, i);
            if (table::contains(&session_registry.sessions, *key)) {
                let session_data = table::borrow(&session_registry.sessions, *key);
                if (current_time > session_data.expires_at) {
                    let _ = table::remove(&mut session_registry.sessions, *key);
                };
            };
            i = i + 1;
        };
    }

    // ===== Admin Functions =====
    entry fun issue_admin_cap(
        _admin_cap: &AdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let new_admin_cap = AdminCap {
            id: object::new(ctx),
            issuer: ctx.sender(),
        };

        transfer::transfer(new_admin_cap, recipient);
    }

    /// admin only
    entry fun verify_user(
        _admin_cap: &AdminCap,
        profile: &mut UserProfile,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let admin_address = ctx.sender();
        profile.is_verified = true;
        profile.updated_at = clock.timestamp_ms();

        event::emit(VerificationStatusChanged {
            user_address: profile.owner,
            profile_id: object::id(profile),
            is_verified: true,
            verified_by: admin_address,
            timestamp: profile.updated_at,
        });
    }

    /// admin only
    entry fun unverify_user(
        _admin_cap: &AdminCap,
        profile: &mut UserProfile,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let admin_address = ctx.sender();
        profile.is_verified = false;
        profile.updated_at = clock.timestamp_ms();

        event::emit(VerificationStatusChanged {
            user_address: profile.owner,
            profile_id: object::id(profile),
            is_verified: false,
            verified_by: admin_address,
            timestamp: profile.updated_at,
        });
    }

    /// admin only
    entry fun update_membership_tier(
        _admin_cap: &AdminCap,
        profile: &mut UserProfile,
        new_tier: u8,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        assert!(new_tier <= MEMBERSHIP_PREMIUM, E_INVALID_MEMBERSHIP_TIER);

        let old_tier = profile.membership_tier;
        profile.membership_tier = new_tier;
        profile.updated_at = clock.timestamp_ms();

        event::emit(MembershipChanged {
            user_address: profile.owner,
            profile_id: object::id(profile),
            old_tier,
            new_tier,
            timestamp: profile.updated_at,
        });
    }

    // ===== View Functions =====
    public fun get_profile_info(profile: &UserProfile): (
        String, // nickname
        String, // bio
        Option<String>, // picture_url
        Option<ID>, // picture_nft_id
        u8, // membership_tier
        bool, // is_verified
        u64, // created_at
        u64  // updated_at
    ) {
        (
            profile.nickname,
            profile.bio,
            profile.picture_url,
            profile.picture_nft_id,
            profile.membership_tier,
            profile.is_verified,
            profile.created_at,
            profile.updated_at
        )
    }

    public fun get_session_count(session_registry: &SessionRegistry): u64 {
        table::length(&session_registry.sessions)
    }

    public fun session_exists(session_registry: &SessionRegistry, public_key: vector<u8>): bool {
        table::contains(&session_registry.sessions, public_key)
    }

    // ===== NFT Functions =====
    entry fun transfer_profile_nft(
        nft: ProfilePictureNFT,
        recipient: address,
        _ctx: &mut TxContext
    ) {
        transfer::transfer(nft, recipient);
    }

    public fun get_nft_info(nft: &ProfilePictureNFT): (String, String, String, u64) {
        (nft.name, nft.description, nft.image_url, nft.created_at)
    }
}
