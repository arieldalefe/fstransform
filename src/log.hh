/*
 * log.hh
 *
 *  Created on: Mar 8, 2011
 *      Author: max
 */

#ifndef FSTRANSFORM_LOG_HH
#define FSTRANSFORM_LOG_HH

#include "check.hh"

#include <errno.h>  // for EINVAL
#include <stdio.h>  // for FILE *
#include <stdarg.h> // for va_list

FT_EXTERN_C_BEGIN
FT_NAMESPACE_BEGIN


/**
 * note 1.1)
 * log subsystem is automatically initialized upon first call to
 * ff_log(), ff_vlog(), ff_log_register() or ff_log_set_threshold().
 *
 * automatic initialization configuration is:
 * print to stderr all WARN messages or more serious, with format FC_FMT_MSG
 * print to stdout all NOTICE messages or less serious, with format FC_FMT_MSG
 */


typedef enum ft_log_level_e { FC_TRACE, FC_DEBUG, FC_INFO, FC_NOTICE, FC_WARN, FC_ERROR, FC_FATAL } ft_log_level;

typedef enum ft_log_fmt_e {
    FC_FMT_MSG, // message only
    FC_FMT_LEVEL_MSG, // level + message
    FC_FMT_DATETIME_LEVEL_MSG, // datetime + level + message
    FC_FMT_DATETIME_LEVEL_CALLER_MSG, // datetime + level + [file.func(line)] + message
} ft_log_fmt;


/**
 * print to log fmt and subsequent printf-style args log stream(s).
 * if err != 0, append ": ", strerror(errno) and "\n"
 * else append "\n"
 * finally return err
 */
#define ff_log(level, err, ...)         ff_logl(FT_THIS_FILE, FT_THIS_FUNCTION, FT_THIS_LINE, level, err, __VA_ARGS__)
#define ff_vlog(level, err, fmt, vargs) ff_logv(FT_THIS_FILE, FT_THIS_FUNCTION, FT_THIS_LINE, level, err, fmt, vargs)

int ff_logl(const char * caller_file, const char * caller_func, int caller_line, ft_log_level level, int err, const char * fmt, ...);
int ff_logv(const char * caller_file, const char * caller_func, int caller_line, ft_log_level level, int err, const char * fmt, va_list args);


#if defined(EINVAL) && EINVAL < 0
#  define ff_log_is_reported(err) ((err) >= 0)
#else
#  define ff_log_is_reported(err) ((err) <= 0)
#endif


/**
 * flush all buffered streams used to log messages for specified level
 */
void ff_log_flush(ft_log_level level);

/**
 * add 'stream' to the list of streams receiving log messages
 * with seriousness between min_level and max_level (inclusive)
 *
 * by default, all WARN messages or more serious are sent to stderr
 * and all NOTICE messages or less serious are sent to stdout
 * note: by default, messages less serious than INFO are suppressed, see ff_log_set_threshold()
 */
void ff_log_register(FILE * stream, ft_log_fmt format, ft_log_level min_level = FC_TRACE, ft_log_level max_level = FC_FATAL);

/**
 * remove 'stream' from the list of streams receiving log messages
 * at least as serious as 'level'.
 */
void ff_log_unregister(FILE * stream, ft_log_level min_level = FC_TRACE, ft_log_level max_level = FC_FATAL);

/**
 * tell ff_log() and ff_vlog() to suppress printing of messages less serious than 'level'.
 *
 * by default, all messages less serious than 'INFO' are suppressed
 */
void ff_log_set_threshold(ft_log_level level);

/**
 * return true if printing specified message level is enabled (i.e. not suppressed)
 */
bool ff_log_is_enabled(ft_log_level level);


FT_NAMESPACE_END
FT_EXTERN_C_END


#endif /* FSTRANSFORM_LOG_HH */
