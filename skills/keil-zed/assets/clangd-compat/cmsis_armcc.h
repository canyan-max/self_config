/**
 ******************************************************************************
 *@file               :   cmsis_armcc.h
 *@brief              :   Editor adapter for explicit ARMCC5 CMSIS includes.
 *@version            :   V1.0
 *@note               :   1 tab == 4 spaces!
 ******************************************************************************
 */

/* define to prevent recursive inclusion ------------------------------------*/
#ifndef KEIL_ZED_CMSIS_ARMCC_H
#define KEIL_ZED_CMSIS_ARMCC_H

/* includes -----------------------------------------------------------------*/
/* Only compile_commands.json adds this directory; Keil must use its vendor
 * header. Reuse real CMSIS intrinsics instead of replacing them with stubs. */
#if defined(__clang__)
#include <cmsis_gcc.h>
#else
#error "This adapter is for clangd analysis only. Remove it from build paths."
#endif

/* define -------------------------------------------------------------------*/

/* typedef ------------------------------------------------------------------*/

/* variables ----------------------------------------------------------------*/

/* function -----------------------------------------------------------------*/

#endif /* KEIL_ZED_CMSIS_ARMCC_H */
/* end of file --------------------------------------------------------------*/
