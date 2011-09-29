/*
 * ui/ui_tty.cc
 *
 *  Created on: Mar 23, 2011
 *      Author: max
 */

#include "../first.hh"

#include <cerrno>

#ifdef FT_HAVE_TERMIOS_H
# include <termios.h>
# include <sys/ioctl.h>
#endif

# include <sys/types.h>
# include <sys/stat.h>
# include <fcntl.h>

#include "../log.hh"        // for ff_log
#include "../vector.hh"     // for fr_vector<T>
#include "../io/io.hh"      // for fr_io
#include "ui_tty.hh"

FT_UI_NAMESPACE_BEGIN

fr_ui_tty::fr_tty_window::fr_tty_window()
    : len(0), h0(0), h(0)
{ }


/** default constructor */
fr_ui_tty::fr_ui_tty()
    : super_type(), this_dev(), this_storage(),
      this_w(0), this_h(0), this_file(NULL), need_clr(true)
{ }


/** destructor */
fr_ui_tty::~fr_ui_tty()
{ }


int fr_ui_tty::init(const char * tty_name)
{
#ifdef TIOCGWINSZ
    struct winsize wsz;
    int err = 0, fd = -1;
    do {
        if ((fd = ::open(tty_name, O_WRONLY|O_NOCTTY)) < 0) {
            err = ff_log(FC_ERROR, errno, "error opening tty '%s'", tty_name);
            break;
        }
        if ((err = ioctl(fd, TIOCGWINSZ, &wsz)) != 0) {
            err = ff_log(FC_ERROR, errno, "error in tty ioctl('%s', TIOCGWINSZ)", tty_name);
            break;
        }
        if ((this_file = fdopen(fd, "w")) == NULL) {
            err = ff_log(FC_ERROR, errno, "error in tty fdopen('%s', \"w\")", tty_name);
            break;
        }
        this_w = (ft_uint) wsz.ws_col;
        this_h = (ft_uint) wsz.ws_row;
        if ((unsigned short)this_w != wsz.ws_col || (unsigned short)this_h != wsz.ws_row) {
            err = ff_log(FC_ERROR, EOVERFLOW, "tty window size overflows for (ft_uint)");
            break;
        }
    } while (0);

    if (err != 0) {
        if (this_file != NULL) {
            if (fclose(this_file) != 0)
                ff_log(FC_WARN, errno, "warning: closing tty '%s' failed", tty_name);
            this_file = NULL;
        }
        if (fd >= 0)
            close(fd);
    }
    return err;
#else /* !TIOCGWINSZ */
    return ENOSYS;
#endif
}

int fr_ui_tty::start(FT_IO_NS fr_io * io)
{
    ft_uoff dev_len = io->dev_length(),
        storage_len = io->job_storage_size(FC_PRIMARY_STORAGE_EXACT_SIZE)
                    + io->job_storage_size(FC_SECONDARY_STORAGE_EXACT_SIZE);

    if ((this_dev.len = dev_len) == 0 || (this_storage.len = storage_len) == 0)
        return ff_log(FC_ERROR, EINVAL, "error: device length or storage length is zero");

    this_storage.h0 = 0;
    this_storage.h = (ft_uint)(0.5 + (double)this_h * this_storage.len / (this_dev.len + this_storage.len));
    if (this_storage.h == 0)
        this_storage.h = 1;
    this_dev.h0 = this_storage.h;
    this_dev.h = this_h - this_storage.h;
    return 0;
}

void fr_ui_tty::show_io_read(fr_from from, ft_uoff offset, ft_uoff length)
{
    const fr_tty_window & window = from == FC_FROM_DEV ? this_dev : this_storage;

    show_io_op(false, window, offset, length);
}

void fr_ui_tty::show_io_write(fr_to to, ft_uoff offset, ft_uoff length)
{
    const fr_tty_window & window = to == FC_TO_DEV ? this_dev : this_storage;

    show_io_op(true, window, offset, length);
}

void fr_ui_tty::show_io_copy(fr_dir dir, ft_uoff from_physical, ft_uoff to_physical, ft_uoff length)
{
    show_io_read(ff_from(dir), from_physical, length);
    show_io_write(ff_to(dir), to_physical, length);
}

void fr_ui_tty::show_io_op(bool is_write, const fr_tty_window & window, ft_uoff offset, ft_uoff length)
{
    if (need_clr) {
        need_clr = false;
        fputs("\033[2J", this_file);
    }
    ft_ull pos = (ft_ull)((double)offset * this_w * window.h / window.len);
    ft_ull len = (ft_ull)(((double)length * this_w * window.h + window.len - 1) / window.len);

    ft_ull y = pos / this_w, x = pos % this_w;
    fprintf(this_file, "\033[3%cm\033[%"FS_ULL";%"FS_ULL"H", (int)(is_write ? '1' : '2'), y+1+window.h0, x+1); /* ANSI colors: 1 = red, 2 = green */

    while (len >= 40) {
        len -= 40;
        fputs("########################################", this_file);
    }
    while (len-- != 0)
        putc('#', this_file);
}

void fr_ui_tty::show_io_flush()
{
    fflush(this_file);
    need_clr = true;
}

FT_UI_NAMESPACE_END