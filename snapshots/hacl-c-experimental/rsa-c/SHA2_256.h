/* This file was auto-generated by KreMLin! */
#include "kremlib.h"
#ifndef __SHA2_256_H
#define __SHA2_256_H


#include "Addition.h"
#include "Comparison.h"
#include "Convert.h"
#include "Shift.h"
#include "Division.h"
#include "Multiplication.h"
#include "Exponentiation.h"
#include "Hacl_Hash_Lib_Create.h"
#include "Hacl_Hash_Lib_LoadStore.h"
#include "Hacl_Hash_SHA2_256.h"
#include "testlib.h"

typedef uint8_t SHA2_256_uint8_t;

typedef uint32_t SHA2_256_uint32_t;

typedef uint64_t SHA2_256_uint64_t;

typedef uint8_t SHA2_256_uint8_ht;

typedef uint32_t SHA2_256_uint32_ht;

typedef uint32_t *SHA2_256_uint32_p;

typedef uint8_t *SHA2_256_uint8_p;

extern uint32_t SHA2_256_size_hash;

extern uint32_t SHA2_256_size_block;

extern uint32_t SHA2_256_size_state;

void SHA2_256_init(uint32_t *state);

void SHA2_256_update(uint32_t *state, uint8_t *data_8);

void SHA2_256_update_multi(uint32_t *state, uint8_t *data, uint32_t n1);

void SHA2_256_update_last(uint32_t *state, uint8_t *data, uint32_t len);

void SHA2_256_finish(uint32_t *state, uint8_t *hash1);

void SHA2_256_hash(uint8_t *hash1, uint8_t *input, uint32_t len);
#endif
