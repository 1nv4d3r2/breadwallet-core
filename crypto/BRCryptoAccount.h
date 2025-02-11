//
//  BRCryptoAccount.h
//  BRCore
//
//  Created by Ed Gamble on 3/19/19.
//  Copyright © 2019 breadwallet. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//  See the CONTRIBUTORS file at the project root for a list of contributors.

#ifndef BRCryptoAccount_h
#define BRCryptoAccount_h

#include <inttypes.h>
#include "BRInt.h"
#include "BRCryptoBase.h"

#ifdef __cplusplus
extern "C" {
#endif

    typedef struct BRCryptoAccountRecord *BRCryptoAccount;

    /**
     * Given a phrase (A BIP-39 PaperKey) dervied the corresponding 'seed'.  This is used
     * exclusive to sign transactions (BTC ones for sure).
     *
     * @param phrase A BIP-32 Paper Key
     *
     * @return A UInt512 seed
     */
    extern UInt512
    cryptoAccountDeriveSeed (const char *phrase);

    /**
     * Generate a BIP-39 PaperKey from a BIP-39 word list
     *
     * @note Asserts if words is itself an invalide BIP-39 word list
     *
     * @param wordList The BIP-39 word list.
     *
     * @return A BIP-39 PaperKey
     */
    extern char *
    cryptoAccountGeneratePaperKey (const char *wordList[]);

    /**
     * Validate a candidate BIP-39 PaperKey with a BIP-39 word list
     *
     * @note Asserts if words is itself an invalide BIP-39 word list
     *
     * @param phrase the candiate paper key
     * @param words the BIP-39 word list
     *
     * @return true if valid; false otherwise
     */
    extern BRCryptoBoolean
    cryptoAccountValidatePaperKey (const char *phrase, const char *words[]);

    /**
     * Validate the number of words in the word list.
     *
     * @param wordsCount number of words
     *
     * @return CRYPTO_TRUE if valid; false otherwise.
     */
    extern BRCryptoBoolean
    cryptoAccountValidateWordsList (size_t wordsCount);

    extern BRCryptoAccount
    cryptoAccountCreate (const char *paperKey, uint64_t timestamp, const char *uids);

    /**
     * Recreate an Account from a serialization
     *
     * @param bytes serialized bytes
     * @param bytesCount serialized bytes count
     *
     * @return The Account, or NULL.  If the serialization is invalid then the account *must be
     * recreated* from the `phrase` (aka 'Paper Key').  A serialization will be invald when the
     * serialization format changes which will *always occur* when a new blockchain is added.  For
     * example, when XRP is added the XRP public key must be serialized; the old serialization w/o
     * the XRP public key will be invalid and the `phrase` is *required* in order to produce the
     * XRP public key.
     */
    extern BRCryptoAccount
    cryptoAccountCreateFromSerialization (const uint8_t *bytes, size_t bytesCount, const char *uids);

    extern uint8_t *
    cryptoAccountSerialize (BRCryptoAccount account, size_t *bytesCount);

    extern BRCryptoBoolean
    cryptoAccountValidateSerialization (BRCryptoAccount account,
                                        const uint8_t *bytes,
                                        size_t bytesCount);

    extern uint64_t
    cryptoAccountGetTimestamp (BRCryptoAccount account);

    extern char *
    cryptoAccountGetFileSystemIdentifier (BRCryptoAccount account);

    extern const char *
    cryptoAccountGetUids (BRCryptoAccount account);

    DECLARE_CRYPTO_GIVE_TAKE (BRCryptoAccount, cryptoAccount);

#ifdef __cplusplus
}
#endif

#endif /* BRCryptoAccount_h */
