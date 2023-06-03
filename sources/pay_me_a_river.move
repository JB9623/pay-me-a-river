module overmind::pay_me_a_river {
    use aptos_std::table;
    use aptos_std::table::Table;
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::coin::Coin;
    use aptos_framework::timestamp;
    use std::string::{Self, String};

    const ESENDER_CAN_NOT_BE_RECEIVER: u64 = 1;
    const ENUMBER_INVALID: u64 = 2;
    const EPAYMENT_DOES_NOT_EXIST: u64 = 3;
    const ESTREAM_DOES_NOT_EXIST: u64 = 4;
    const ESTREAM_IS_ACTIVE: u64 = 5;
    const ESIGNER_ADDRESS_IS_NOT_SENDER_OR_RECEIVER: u64 = 6;

    struct Stream has store {
        sender: address,
        receiver: address,
        length_in_seconds: u64,
        start_time: u64,
        coins: Coin<AptosCoin>,
    }

    struct Payments has key {
        streams: Table<address, Stream>,
    }

    /// This turns a u128 into its UTF-8 string equivalent.
    public fun u128_to_string(value: u128): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    inline fun check_sender_is_not_receiver(sender: address, receiver: address) {
        assert!(sender != receiver, ESENDER_CAN_NOT_BE_RECEIVER);
    }

    inline fun check_number_is_valid(number: u64) {
        assert!(number > 0, ENUMBER_INVALID);
    }

    inline fun check_payment_exists(sender_address: address) {
        let payment_exists = exists<Payments>(sender_address);
        assert!(payment_exists, EPAYMENT_DOES_NOT_EXIST);
    }

    inline fun check_stream_exists(payments: &Payments, stream_address: address) {
        assert!(
            table::contains(&payments.streams, stream_address), 
            ESTREAM_DOES_NOT_EXIST
        );
    }

    inline fun check_stream_is_not_active(payments: &Payments, stream_address: address) {
        let stream = table::borrow(&payments.streams, stream_address);
        assert!(stream.start_time == 0, ESTREAM_IS_ACTIVE);
    }

    inline fun check_signer_address_is_sender_or_receiver(
        sender_address: address,
        signer_address: address,
        receiver_address: address
    ) {
        assert!(signer_address == sender_address || signer_address == receiver_address, 
            ESIGNER_ADDRESS_IS_NOT_SENDER_OR_RECEIVER);
    }

    inline fun calculate_stream_claim_amount(total_amount: u64, start_time: u64, length_in_seconds: u64): u64 {
        let _claim_amount: u64 = 0;
        
        let current_time = timestamp::now_seconds();
        if (current_time >= start_time + length_in_seconds) {
            _claim_amount = total_amount
        } else {
            _claim_amount = total_amount * (length_in_seconds / (current_time - start_time));
        };

        _claim_amount
    }

    public entry fun create_stream(
        account: &signer,
        receiver_address: address,
        amount: u64,
        length_in_seconds: u64
    ) acquires Payments {

        let sender_account = signer::address_of(account);

        check_sender_is_not_receiver(sender_account, receiver_address);

        check_number_is_valid(amount);
        
        let coins = coin::withdraw<AptosCoin>(account, amount);
        let start_time = 0;

        if (exists<Payments>(sender_account)) {
            let payment_store = borrow_global_mut<Payments>(sender_account);

            // if (!table::contains(&payment_store.streams, sender_account)) {
            //     table::add(&mut payment_store.streams, sender_account, Stream {
            //         sender: sender_account,
            //         receiver : receiver_address,
            //         length_in_seconds,
            //         start_time,
            //         coins
            //     });
            // };
        } else {
            let registry_seed = u128_to_string((timestamp::now_microseconds() as u128));
            string::append(&mut registry_seed, string::utf8(b"pay_me_a_river"));        
            let (token_resource, _) = account::create_resource_account(account, *string::bytes(&registry_seed));

            // TODO: register Aptos coin to resource account
            coin::register<AptosCoin>(&token_resource); 

            let streams = table::new();
            table::add(&mut streams, sender_account, Stream {
                sender: sender_account,
                receiver : receiver_address,
                length_in_seconds,
                start_time,
                coins
            });
            let payment = Payments {streams};
            move_to(account, payment);
        };
    }

    public entry fun accept_stream(account: &signer, sender_address: address) acquires Payments {

        let _ = signer::address_of(account);

        check_payment_exists(sender_address);

        let payment_store = borrow_global_mut<Payments>(sender_address);

        check_stream_exists(payment_store, sender_address);

        check_stream_is_not_active(payment_store, sender_address);

        let stream = table::borrow_mut(&mut payment_store.streams, sender_address);

        let start_time = timestamp::now_seconds();

        stream.start_time = start_time;

    }

    public entry fun claim_stream(account: &signer, sender_address: address) acquires Payments {

        let receiver_address = signer::address_of(account);

        check_payment_exists(sender_address);

        let payment_store = borrow_global_mut<Payments>(sender_address);

        check_stream_exists(payment_store, sender_address);

        let stream = table::borrow_mut(&mut payment_store.streams, sender_address);

        let claim_amount = calculate_stream_claim_amount(
            coin::value(&stream.coins), 
            stream.start_time, 
            stream.length_in_seconds
        );

        let claim_coin = coin::extract(&mut stream.coins, claim_amount);

        coin::deposit<AptosCoin>(receiver_address, claim_coin);
    }

    public entry fun cancel_stream(
        account: &signer,
        sender_address: address,
        receiver_address: address
    ) acquires Payments {

        let account_address = signer::address_of(account);

        check_payment_exists(sender_address);

        check_sender_is_not_receiver(sender_address, receiver_address);

        check_signer_address_is_sender_or_receiver(sender_address, account_address, receiver_address);

        let payment_store = borrow_global_mut<Payments>(sender_address);
        
        // table::remove(&mut payment_store.streams, sender_address);
        // check_stream_exists(payment_store, sender_address);

        // let stream = table::borrow_mut(&mut payment_store.streams, sender_address);

        // let coin = coin::extract_all(&mut stream.coins);

        // coin::deposit<AptosCoin>(sender_address, coin);

    }

    #[view]
    public fun get_stream(sender_address: address, receiver_address: address): (u64, u64, u64) acquires Payments {

        check_payment_exists(sender_address);

        check_sender_is_not_receiver(sender_address, receiver_address);

        let payment_store = borrow_global<Payments>(sender_address);

        check_stream_exists (payment_store, sender_address);

        let stream = table::borrow(&payment_store.streams, sender_address);

        (stream.length_in_seconds, stream.start_time, coin::value(&stream.coins))
    }
}