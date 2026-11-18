/*
 * BasedOS: which keys are held right now, on every input device, in one go (EVIOCGKEY, so a key
 * held since before boot counts). For the boot-key actions (frontend-session, boot-keys.conf).
 *
 *   basedos-keys          the codes held, as decimal Linux key codes, one per line
 *   basedos-keys <code>   exit 0 if that key is held, 1 if not
 *
 * A few milliseconds in all, where evtest --query costs about 0.04 s for each key.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define NBITS (KEY_MAX + 1)

int main(int argc, char **argv)
{
	unsigned char held[NBITS / 8 + 1] = { 0 };
	int want = argc > 1 ? atoi(argv[1]) : -1;
	DIR *d = opendir("/dev/input");
	struct dirent *e;

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
