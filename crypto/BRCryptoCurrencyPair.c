//
//  BRCryptoCurrencyPair.c
//  BRCore
//
//  Created by Ed Gamble on 3/19/19.
//  Copyright © 2019 breadwallet. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#include "BRCryptoCurrencyPair.h"

#include <stdlib.h>

struct BRCryptoCurrencyPairRecord {
    BRCryptoUnit baseUnit;
    BRCryptoUnit quoteUnit;
    double exchangeRate;
};

extern BRCryptoCurrencyPair
cryptoCurrencyPairCreate (BRCryptoUnit baseUnit,
                          BRCryptoUnit quoteUnit,
                          double exchangeRate) {
    BRCryptoCurrencyPair pair = malloc (sizeof (struct BRCryptoCurrencyPairRecord));

    pair->baseUnit = baseUnit;   // RefCount
    pair->quoteUnit = quoteUnit; // RefCount
    pair->exchangeRate = exchangeRate;

    return pair;
}


/// In EUR/USD=1.2500, the `baseCurrecny` is EUR.

extern BRCryptoAmount
exchangeAsBase (BRCryptoCurrencyPair pair,
                BRCryptoAmount amount) {
    //        guard let amountValue = amount.coerce(unit: baseUnit).double else { return nil }
    //        return Amount (value: amountValue * exchangeRate, unit: quoteUnit)
    return NULL;
}

extern BRCryptoAmount
exchangeAsQuote (BRCryptoCurrencyPair pair,
                 BRCryptoAmount amount) {
    // guard let amountValue = amount.coerce(unit: quoteUnit).double else { return nil }
    //return Amount (value: amountValue / exchangeRate, unit: baseUnit)
    return NULL;
}
