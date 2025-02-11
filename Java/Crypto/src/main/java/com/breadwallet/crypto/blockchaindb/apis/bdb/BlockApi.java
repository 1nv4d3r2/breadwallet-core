/*
 * Created by Michael Carrara <michael.carrara@breadwallet.com> on 7/1/19.
 * Copyright (c) 2019 Breadwinner AG.  All right reserved.
*
 * See the LICENSE file at the project root for license information.
 * See the CONTRIBUTORS file at the project root for a list of contributors.
 */
package com.breadwallet.crypto.blockchaindb.apis.bdb;

import android.support.annotation.Nullable;

import com.breadwallet.crypto.blockchaindb.apis.PageInfo;
import com.breadwallet.crypto.blockchaindb.apis.PagedCompletionHandler;
import com.breadwallet.crypto.blockchaindb.errors.QueryError;
import com.breadwallet.crypto.blockchaindb.models.bdb.Block;
import com.breadwallet.crypto.utility.CompletionHandler;
import com.google.common.collect.ImmutableListMultimap;
import com.google.common.collect.ImmutableMultimap;
import com.google.common.collect.Multimap;
import com.google.common.primitives.UnsignedLong;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;

public class BlockApi {

    private final BdbApiClient jsonClient;
    private final ExecutorService executorService;

    public BlockApi(BdbApiClient jsonClient, ExecutorService executorService) {
        this.jsonClient = jsonClient;
        this.executorService = executorService;
    }

    public void getBlocks(String id,
                          UnsignedLong beginBlockNumber,
                          UnsignedLong endBlockNumber,
                          boolean includeRaw,
                          boolean includeTx,
                          boolean includeTxRaw,
                          boolean includeTxProof,
                          @Nullable Integer maxPageSize,
                          CompletionHandler<List<Block>, QueryError> handler) {
        ImmutableListMultimap.Builder<String, String> paramsBuilder = ImmutableListMultimap.builder();
        paramsBuilder.put("blockchain_id", id);
        paramsBuilder.put("include_raw", String.valueOf(includeRaw));
        paramsBuilder.put("include_tx", String.valueOf(includeTx));
        paramsBuilder.put("include_tx_raw", String.valueOf(includeTxRaw));
        paramsBuilder.put("include_tx_proof", String.valueOf(includeTxProof));
        paramsBuilder.put("start_height", beginBlockNumber.toString());
        paramsBuilder.put("end_height", endBlockNumber.toString());
        if (null != maxPageSize) paramsBuilder.put("max_page_size", maxPageSize.toString());
        ImmutableMultimap<String, String> params = paramsBuilder.build();

        PagedCompletionHandler<List<Block>, QueryError> pagedHandler = createPagedResultsHandler(handler);
        jsonClient.sendGetForArrayWithPaging("blocks", params, Block::asBlocks, pagedHandler);
    }

    public void getBlock(String id, boolean includeRaw,
                         boolean includeTx, boolean includeTxRaw, boolean includeTxProof,
                         CompletionHandler<Block, QueryError> handler) {
        Multimap<String, String> params = ImmutableListMultimap.of(
                "include_raw", String.valueOf(includeRaw),
                "include_tx", String.valueOf(includeTx),
                "include_tx_raw", String.valueOf(includeTxRaw),
                "include_tx_proof", String.valueOf(includeTxProof));

        jsonClient.sendGetWithId("blocks", id, params, Block::asBlock, handler);
    }

    private void submitGetNextBlocks(String nextUrl, PagedCompletionHandler<List<Block>, QueryError> handler) {
        executorService.submit(() -> getNextBlocks(nextUrl, handler));
    }

    private void getNextBlocks(String nextUrl, PagedCompletionHandler<List<Block>, QueryError> handler) {
        jsonClient.sendGetForArrayWithPaging("blocks", nextUrl, Block::asBlocks, handler);
    }

    private PagedCompletionHandler<List<Block>, QueryError> createPagedResultsHandler(CompletionHandler<List<Block>, QueryError> handler) {
        List<Block> allResults = new ArrayList<>();
        return new PagedCompletionHandler<List<Block>, QueryError>() {
            @Override
            public void handleData(List<Block> results, PageInfo info) {
                allResults.addAll(results);

                if (info.nextUrl == null) {
                    handler.handleData(allResults);
                } else {
                    submitGetNextBlocks(info.nextUrl, this);
                }
            }

            @Override
            public void handleError(QueryError error) {
                handler.handleError(error);
            }
        };
    }
}
