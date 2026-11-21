/*
 * BasedOS: which keys are held right now, on every input device, in one go (EVIOCGKEY, so a key
 * held since before boot counts). For the boot-key actions (frontend-session, boot-keys.conf).
 *
 *   basedos-keys               the codes held, as decimal Linux key codes, one per line
 *   basedos-keys <code>        exit 0 if that key is held, 1 if not
 *   basedos-keys --wait <ms>   wait for the next key press on any input device and print its
 *                              code; exit 1 if none comes within <ms> milliseconds (0: wait for
 *                              ever). Reads the devices' events, so a quick tap counts where
 *                              polling what's held could miss it; presses before it started
 *                              don't count.
 *   basedos-keys --watch       print every key press's code as it comes, one per line, until
 *                              killed (or no input device is left). One reader for a whole
 *                              screen, so no tap falls between two runs of --wait (the recovery
 *                              card's tap sequence reads it through a FIFO).
 *
 * A few milliseconds in all, where evtest --query costs about 0.04 s for each key.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define NBITS (KEY_MAX + 1)
#define MAXDEV 32

static long now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000L;
}

/* open_inputs: every /dev/input/event* for reading, in p; how many. */
static int open_inputs(struct pollfd *p)
{
	int n = 0;
	DIR *d = opendir("/dev/input");
	struct dirent *e;

	if (!d)
		return 0;
	while ((e = readdir(d)) && n < MAXDEV) {
		char path[300];
		int fd;

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		p[n].fd = fd;
		p[n].events = POLLIN;
		n++;
	}
	closedir(d);
	return n;
}

/* next_press: the code of the next key press on the devices in p, -1 once <end> (ms, 0: none) has
 * passed, -2 once no device is left (each one that hangs up or fails is dropped: poll would
 * otherwise report it ready at once, for ever). */
static int next_press(struct pollfd *p, int n, long end)
{
	for (;;) {
		long left = -1;
		int open = 0;

		for (int i = 0; i < n; i++)
			open += p[i].fd >= 0;
		if (!open)
			return -2;
		if (end) {
			left = end - now_ms();
			if (left <= 0)
				return -1;
		}
		if (poll(p, n, (int)left) <= 0)
			continue;
		for (int i = 0; i < n; i++) {
			struct input_event ev;

			if (p[i].fd < 0)
				continue;
			if (p[i].revents & (POLLHUP | POLLERR | POLLNVAL)) {
				close(p[i].fd);
				p[i].fd = -1;
				continue;
			}
			if (!(p[i].revents & POLLIN))
				continue;
			while (read(p[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev))
				if (ev.type == EV_KEY && ev.value == 1)
					return ev.code;
		}
	}
}

static int wait_press(long timeout)
{
	struct pollfd p[MAXDEV];
	int n = open_inputs(p), c;

	if (!n)
		return 2;
	c = next_press(p, n, timeout > 0 ? now_ms() + timeout : 0);
	if (c == -2)
		return 2;
	if (c < 0)
		return 1;
	printf("%d\n", c);
	return 0;
}

static int watch_presses(void)
{
	struct pollfd p[MAXDEV];
	int n = open_inputs(p), c;

	if (!n)
		return 2;
	while ((c = next_press(p, n, 0)) >= 0) {
		printf("%d\n", c);
		fflush(stdout);
	}
	return 2;
}

int main(int argc, char **argv)
{
	unsigned char held[NBITS / 8 + 1] = { 0 };
	int want;
	DIR *d;
	struct dirent *e;

	if (argc > 1 && !strcmp(argv[1], "--wait"))
		return wait_press(argc > 2 ? atol(argv[2]) : 0);
	if (argc > 1 && !strcmp(argv[1], "--watch"))
		return watch_presses();
	want = argc > 1 ? atoi(argv[1]) : -1;
	d = opendir("/dev/input");
	if (!d)
		return 2;
	while ((e = readdir(d))) {
		unsigned char state[NBITS / 8 + 1] = { 0 };
		char path[300];
		int fd;

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGKEY(sizeof(state)), state) >= 0)
			for (size_t i = 0; i < sizeof(state); i++)
				held[i] |= state[i];
		close(fd);
	}
	closedir(d);

	if (want >= 0)
		return (want < NBITS && (held[want / 8] & (1 << (want % 8)))) ? 0 : 1;
	for (int c = 0; c < NBITS; c++)
		if (held[c / 8] & (1 << (c % 8)))
			printf("%d\n", c);
	return 0;
}
