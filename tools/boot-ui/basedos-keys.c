/*
 * BasedOS: which keys are held right now, on every input device, in one go (EVIOCGKEY, so a key
 * held since before boot counts). For the boot-key actions (frontend-session, boot-keys.conf).
 *
 *   basedos-keys               the codes held, as decimal Linux key codes, one per line
 *   basedos-keys <code>        exit 0 if that key is held, 1 if not
 *   basedos-keys --wait <ms>   wait for the next key press on any input device and print its
 *                              code; exit 1 if none comes within <ms> milliseconds (0: wait for
 *                              ever). Reads the devices' events, so a tap can't fall between two
 *                              looks the way it can when polling what's held (the recovery card's
 *                              tap sequence).
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

static int wait_press(long timeout)
{
	struct pollfd p[MAXDEV];
	int n = 0;
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	long end = timeout > 0 ? now_ms() + timeout : 0;

	if (!d)
		return 2;
	while ((e = readdir(d)) && n < MAXDEV) {
		char path[300];
		int fd;

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		p[n].fd = fd;
		p[n].events = POLLIN;
		n++;
	}
	closedir(d);
	if (!n)
		return 2;
	for (;;) {
		long left = -1;

		if (end) {
			left = end - now_ms();
			if (left <= 0)
				return 1;
		}
		if (poll(p, n, (int)left) <= 0)
			continue;
		for (int i = 0; i < n; i++) {
			struct input_event ev;

			if (!(p[i].revents & POLLIN))
				continue;
			while (read(p[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev))
				if (ev.type == EV_KEY && ev.value == 1) {
					printf("%d\n", ev.code);
					return 0;
				}
		}
	}
}

int main(int argc, char **argv)
{
	unsigned char held[NBITS / 8 + 1] = { 0 };
	int want;
	DIR *d;
	struct dirent *e;

	if (argc > 1 && !strcmp(argv[1], "--wait"))
		return wait_press(argc > 2 ? atol(argv[2]) : 0);
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
