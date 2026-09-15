// SPDX-License-Identifier: GPL-2.0
/*
 * Synthesise the display TE pulse on a panel-less Quest 1.
 *
 * Camera frame sync rides a 72 Hz tearing-effect pulse. Stock, it comes from
 * the left panel into GPIO 10, where the syncboss driver takes an edge IRQ.
 * Detach the panels and that IRQ sits at zero, capture timestamps never
 * resolve, and tracking never starts.
 *
 * TE is only needed to bootstrap. Pull the panels after boot and tracking
 * keeps running, so a synthetic pulse only has to get the pipeline going.
 *
 * Driven through TLMM directly rather than gpiolib, because syncboss already
 * holds the line and gpio_request() would be refused. The pad still generates
 * real edges, so the stock handler runs untouched.
 */
#include <linux/hrtimer.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/delay.h>

/*
 * MSM8998 TLMM is tiled. Pin registers sit at base + tile + 0x1000 * id, not
 * a flat base + 0x1000 * id. Get that wrong and reads return zero while the
 * timer ticks happily. GPIO 10 is EAST, alt function MDP VSYNC.
 */
#define TLMM_BASE	0x03400000u
#define TLMM_STRIDE	0x1000u
#define TILE_EAST	0x900000u
#define TILE_NORTH	0x500000u
#define TILE_WEST	0x100000u
#define TLMM_CFG(n)	(TLMM_BASE + tile + (TLMM_STRIDE * (n)))
#define TLMM_INOUT(n)	(TLMM_CFG(n) + 4)

#define CFG_OE		BIT(9)
#define INOUT_OUT	BIT(1)

/* 72.00001 Hz, matching the panel's presDeadline. */
static unsigned int period_ns = 13888888;
module_param(period_ns, uint, 0644);
MODULE_PARM_DESC(period_ns, "TE period in nanoseconds (default 13888888 = 72 Hz)");

static unsigned int gpio = 10;
module_param(gpio, uint, 0444);
MODULE_PARM_DESC(gpio, "TLMM GPIO carrying syncboss timesync (default 10)");

static unsigned int tile = TILE_EAST;
module_param(tile, uint, 0444);
MODULE_PARM_DESC(tile, "TLMM tile offset (EAST 0x900000, NORTH 0x500000, WEST 0x100000)");

/* The handler is edge triggered, so width only has to be wide enough to land. */
static unsigned int pulse_ns = 100000;
module_param(pulse_ns, uint, 0644);
MODULE_PARM_DESC(pulse_ns, "pulse width in nanoseconds (default 100000)");

static void __iomem *cfg_reg;
static void __iomem *inout_reg;
static struct hrtimer te_timer;
static u32 saved_cfg;
static u64 edges;

static enum hrtimer_restart te_tick(struct hrtimer *t)
{
	/* Assert on one tick, clear on the next. Busy-waiting here would be rude. */
	static bool level;

	level = !level;
	writel_relaxed(level ? INOUT_OUT : 0, inout_reg);
	edges++;

	hrtimer_forward_now(t, ns_to_ktime(level ? pulse_ns
						 : period_ns - pulse_ns));
	return HRTIMER_RESTART;
}

static int __init sa_init(void)
{
	u32 cfg;

	cfg_reg = ioremap(TLMM_CFG(gpio), 4);
	inout_reg = ioremap(TLMM_INOUT(gpio), 4);
	if (!cfg_reg || !inout_reg) {
		pr_err("SeperationAnxiety: ioremap of TLMM gpio %u failed\n", gpio);
		goto fail;
	}

	/* Keep the original config so unload can hand the line back. */
	saved_cfg = readl_relaxed(cfg_reg);

	/*
	 * Refuse to fight a panel that is already driving TE. Live TE toggles
	 * at 72 Hz, so a 45 ms sample is plenty to spot it. This cannot catch a
	 * panel that has not started yet, so it only guards manual insmod.
	 */
	{
		u32 first = readl_relaxed(inout_reg) & 1;
		int i;

		for (i = 0; i < 45; i++) {
			usleep_range(1000, 1200);
			if ((readl_relaxed(inout_reg) & 1) != first) {
				pr_warn("SeperationAnxiety: gpio %u already toggling, a panel is driving TE. Refusing.\n",
					gpio);
				iounmap(cfg_reg);
				iounmap(inout_reg);
				return -EBUSY;
			}
		}
	}

	cfg = saved_cfg | CFG_OE;
	writel_relaxed(0, inout_reg);
	writel_relaxed(cfg, cfg_reg);

	hrtimer_init(&te_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	te_timer.function = te_tick;
	hrtimer_start(&te_timer, ns_to_ktime(period_ns), HRTIMER_MODE_REL);

	pr_info("SeperationAnxiety: driving TE on gpio %u @ %#x at %u ns (cfg %#x -> %#x)\n",
		gpio, TLMM_CFG(gpio), period_ns, saved_cfg, cfg);
	return 0;

fail:
	if (cfg_reg)
		iounmap(cfg_reg);
	if (inout_reg)
		iounmap(inout_reg);
	return -ENODEV;
}

static void __exit sa_exit(void)
{
	hrtimer_cancel(&te_timer);
	writel_relaxed(0, inout_reg);
	writel_relaxed(saved_cfg, cfg_reg);
	iounmap(cfg_reg);
	iounmap(inout_reg);
	pr_info("SeperationAnxiety: stopped after %llu edges\n", edges);
}

module_init(sa_init);
module_exit(sa_exit);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Synthetic display TE pulse for panel-less Quest 1 tracking");
