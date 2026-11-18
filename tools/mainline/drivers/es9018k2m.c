// SPDX-License-Identifier: GPL-2.0-only
/*
 * ESS ES9018K2M stereo DAC, as on the GameKiddy GKD 350H Ultra.
 *
 * The chip runs from its own oscillator and takes I2S as a consumer, 32-bit slots. Its
 * registers 0x00-0x1e configure it and 0x40-0x47 report status; 0x1f-0x3f don't exist (no ack).
 * The board switches the speaker amplifier and the headphone path with two GPIOs and detects
 * headphones with a third; the speaker and headphone outputs are DAPM widgets driving those
 * GPIOs, and a jack on the detect GPIO swaps them.
 *
 * Unlike the stock (BSP) driver, the register cache only holds what this driver wrote, and it
 * is written back on resume: the chip loses its registers in deep sleep, and the stock driver's
 * cache kept the old volume while the chip woke at 0 dB.
 */
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/regmap.h>
#include <sound/jack.h>
#include <sound/pcm_params.h>
#include <sound/soc.h>
#include <sound/tlv.h>

#define ES9018K2M_INPUT_CONFIG		0x01
#define ES9018K2M_DEEMPHASIS		0x06
#define ES9018K2M_GENERAL		0x07
#define ES9018K2M_GENERAL_MUTE		BIT(0)
#define ES9018K2M_VOLUME1		0x0f
#define ES9018K2M_VOLUME2		0x10
#define ES9018K2M_LAST_CONFIG		0x1e
#define ES9018K2M_STATUS		0x40
#define ES9018K2M_LAST_STATUS		0x47

struct es9018k2m {
	struct regmap *regmap;
	struct gpio_desc *spk_en;
	struct gpio_desc *hp_en;
	struct snd_soc_jack jack;
	struct snd_soc_jack_gpio jack_gpio;
};

static bool es9018k2m_readable(struct device *dev, unsigned int reg)
{
	return reg <= ES9018K2M_LAST_CONFIG ||
	       (reg >= ES9018K2M_STATUS && reg <= ES9018K2M_LAST_STATUS);
}

static bool es9018k2m_writeable(struct device *dev, unsigned int reg)
{
	return reg <= ES9018K2M_LAST_CONFIG;
}

static bool es9018k2m_volatile(struct device *dev, unsigned int reg)
{
	return reg >= ES9018K2M_STATUS;
}

static const struct regmap_config es9018k2m_regmap = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = ES9018K2M_LAST_STATUS,
	.readable_reg = es9018k2m_readable,
	.writeable_reg = es9018k2m_writeable,
	.volatile_reg = es9018k2m_volatile,
	/* No defaults: only what this driver writes is cached, and all of it is synced back. */
	.cache_type = REGCACHE_MAPLE,
};

/*
 * "<pin> Switch" for one of this component's own DAPM pins. SOC_DAPM_PIN_SWITCH is for card
 * controls (its handlers take the control's owner for the card) and oopses here.
 */
#define ES9018K2M_PIN_SWITCH(xname) {					\
	.iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname " Switch",	\
	.info = snd_soc_dapm_info_pin_switch,				\
	.get = snd_soc_dapm_get_component_pin_switch,			\
	.put = snd_soc_dapm_put_component_pin_switch,			\
	.private_value = (unsigned long)xname }

/* 0.5 dB steps of attenuation: register 0 is 0 dB, 255 is -127.5 dB. */
static const DECLARE_TLV_DB_SCALE(es9018k2m_volume_tlv, -12750, 50, 1);

static const struct snd_kcontrol_new es9018k2m_controls[] = {
	/* The stock driver's name and range (255 = 0 dB), which spruce's VOLUME_CONTROL uses. */
	SOC_DOUBLE_R_TLV("Digital Playback Volume", ES9018K2M_VOLUME1, ES9018K2M_VOLUME2,
			 0, 255, 1, es9018k2m_volume_tlv),
	ES9018K2M_PIN_SWITCH("Speaker"),
	ES9018K2M_PIN_SWITCH("Headphone"),
};

static int es9018k2m_spk_event(struct snd_soc_dapm_widget *w, struct snd_kcontrol *k, int event)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(snd_soc_dapm_to_component(w->dapm));

	gpiod_set_value_cansleep(es->spk_en, SND_SOC_DAPM_EVENT_ON(event));
	return 0;
}

static int es9018k2m_hp_event(struct snd_soc_dapm_widget *w, struct snd_kcontrol *k, int event)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(snd_soc_dapm_to_component(w->dapm));

	gpiod_set_value_cansleep(es->hp_en, SND_SOC_DAPM_EVENT_ON(event));
	return 0;
}

static const struct snd_soc_dapm_widget es9018k2m_widgets[] = {
	SND_SOC_DAPM_DAC("DAC", "Playback", SND_SOC_NOPM, 0, 0),
	SND_SOC_DAPM_SPK("Speaker", es9018k2m_spk_event),
	SND_SOC_DAPM_HP("Headphone", es9018k2m_hp_event),
};

static const struct snd_soc_dapm_route es9018k2m_routes[] = {
	{ "Speaker", NULL, "DAC" },
	{ "Headphone", NULL, "DAC" },
};

/* Headphones in: the headphone path on, the speaker off; out: the other way round. */
static struct snd_soc_jack_pin es9018k2m_jack_pins[] = {
	{ .pin = "Headphone", .mask = SND_JACK_HEADPHONE },
	{ .pin = "Speaker", .mask = SND_JACK_HEADPHONE, .invert = 1 },
};

static int es9018k2m_component_probe(struct snd_soc_component *component)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(component);
	struct device *dev = component->dev;
	unsigned int status;
	int ret;

	ret = regmap_read(es->regmap, ES9018K2M_STATUS, &status);
	if (ret)
		return dev_err_probe(dev, ret, "can't read the chip status\n");
	dev_info(dev, "ES9018K2M, status %#04x\n", status);

	if (!gpiod_count(dev, "hp-det"))
		return 0;
	ret = snd_soc_card_jack_new_pins(component->card, "Headphones", SND_JACK_HEADPHONE,
					 &es->jack, es9018k2m_jack_pins,
					 ARRAY_SIZE(es9018k2m_jack_pins));
	if (ret)
		return dev_err_probe(dev, ret, "can't create the headphone jack\n");
	es->jack_gpio.name = "hp-det";
	es->jack_gpio.report = SND_JACK_HEADPHONE;
	es->jack_gpio.debounce_time = 150;
	es->jack_gpio.gpiod_dev = dev;
	ret = snd_soc_jack_add_gpios(&es->jack, 1, &es->jack_gpio);
	if (ret)
		return dev_err_probe(dev, ret, "can't watch the headphone detect GPIO\n");
	return 0;
}

static void es9018k2m_component_remove(struct snd_soc_component *component)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(component);

	if (es->jack_gpio.desc)
		snd_soc_jack_free_gpios(&es->jack, 1, &es->jack_gpio);
}

static int es9018k2m_suspend(struct snd_soc_component *component)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(component);

	regcache_cache_only(es->regmap, true);
	regcache_mark_dirty(es->regmap);
	return 0;
}

static int es9018k2m_resume(struct snd_soc_component *component)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(component);

	regcache_cache_only(es->regmap, false);
	return regcache_sync(es->regmap);
}

static const struct snd_soc_component_driver es9018k2m_component = {
	.probe = es9018k2m_component_probe,
	.remove = es9018k2m_component_remove,
	.suspend = es9018k2m_suspend,
	.resume = es9018k2m_resume,
	.controls = es9018k2m_controls,
	.num_controls = ARRAY_SIZE(es9018k2m_controls),
	.dapm_widgets = es9018k2m_widgets,
	.num_dapm_widgets = ARRAY_SIZE(es9018k2m_widgets),
	.dapm_routes = es9018k2m_routes,
	.num_dapm_routes = ARRAY_SIZE(es9018k2m_routes),
	.endianness = 1,
};

static int es9018k2m_set_fmt(struct snd_soc_dai *dai, unsigned int fmt)
{
	if ((fmt & SND_SOC_DAIFMT_CLOCK_PROVIDER_MASK) != SND_SOC_DAIFMT_CBC_CFC)
		return -EINVAL;
	if ((fmt & SND_SOC_DAIFMT_FORMAT_MASK) != SND_SOC_DAIFMT_I2S)
		return -EINVAL;
	return 0;
}

static int es9018k2m_mute(struct snd_soc_dai *dai, int mute, int direction)
{
	struct es9018k2m *es = snd_soc_component_get_drvdata(dai->component);

	return regmap_update_bits(es->regmap, ES9018K2M_GENERAL, ES9018K2M_GENERAL_MUTE,
				  mute ? ES9018K2M_GENERAL_MUTE : 0);
}

static const struct snd_soc_dai_ops es9018k2m_dai_ops = {
	.set_fmt = es9018k2m_set_fmt,
	.mute_stream = es9018k2m_mute,
	.no_capture_mute = 1,
};

static struct snd_soc_dai_driver es9018k2m_dai = {
	.name = "es9018k2m-hifi",
	.playback = {
		.stream_name = "Playback",
		.channels_min = 2,
		.channels_max = 2,
		.rates = SNDRV_PCM_RATE_8000_384000,
		.formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE |
			   SNDRV_PCM_FMTBIT_S32_LE,
	},
	.ops = &es9018k2m_dai_ops,
};

static int es9018k2m_i2c_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct es9018k2m *es;

	es = devm_kzalloc(dev, sizeof(*es), GFP_KERNEL);
	if (!es)
		return -ENOMEM;
	i2c_set_clientdata(client, es);

	es->regmap = devm_regmap_init_i2c(client, &es9018k2m_regmap);
	if (IS_ERR(es->regmap))
		return dev_err_probe(dev, PTR_ERR(es->regmap), "can't set up the regmap\n");
	es->spk_en = devm_gpiod_get_optional(dev, "spk-en", GPIOD_OUT_LOW);
	if (IS_ERR(es->spk_en))
		return dev_err_probe(dev, PTR_ERR(es->spk_en), "can't get spk-en\n");
	es->hp_en = devm_gpiod_get_optional(dev, "hp-en", GPIOD_OUT_LOW);
	if (IS_ERR(es->hp_en))
		return dev_err_probe(dev, PTR_ERR(es->hp_en), "can't get hp-en\n");

	return devm_snd_soc_register_component(dev, &es9018k2m_component, &es9018k2m_dai, 1);
}

static const struct of_device_id es9018k2m_of_match[] = {
	{ .compatible = "ess,es9018k2m" },
	{ }
};
MODULE_DEVICE_TABLE(of, es9018k2m_of_match);

static const struct i2c_device_id es9018k2m_i2c_id[] = {
	{ "es9018k2m" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, es9018k2m_i2c_id);

static struct i2c_driver es9018k2m_driver = {
	.driver = {
		.name = "es9018k2m",
		.of_match_table = es9018k2m_of_match,
	},
	.probe = es9018k2m_i2c_probe,
	.id_table = es9018k2m_i2c_id,
};
module_i2c_driver(es9018k2m_driver);

MODULE_DESCRIPTION("ESS ES9018K2M DAC");
MODULE_LICENSE("GPL");
