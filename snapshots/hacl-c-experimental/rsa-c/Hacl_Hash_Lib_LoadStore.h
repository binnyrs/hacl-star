/* This file was auto-generated by KreMLin! */
#include "kremlib.h"
#ifndef __Hacl_Hash_Lib_LoadStore_H
#define __Hacl_Hash_Lib_LoadStore_H


#include "Addition.h"
#include "Comparison.h"
#include "Convert.h"
#include "Shift.h"
#include "Division.h"
#include "Multiplication.h"
#include "Exponentiation.h"
#include "Hacl_Hash_Lib_Create.h"
#include "testlib.h"

typedef uint8_t *Hacl_Hash_Lib_LoadStore_uint8_p;

void
Hacl_Hash_Lib_LoadStore_uint32s_from_be_bytes(uint32_t *output, uint8_t *input, uint32_t len);

void
Hacl_Hash_Lib_LoadStore_uint32s_to_be_bytes(uint8_t *output, uint32_t *input, uint32_t len);

void
Hacl_Hash_Lib_LoadStore_uint64s_from_be_bytes(uint64_t *output, uint8_t *input, uint32_t len);

void
Hacl_Hash_Lib_LoadStore_uint64s_to_be_bytes(uint8_t *output, uint64_t *input, uint32_t len);
#endif
