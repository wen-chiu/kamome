import { Config } from "@remotion/cli/config";

// Footage, music and voice live outside the repository.
Config.setPublicDir(`${process.env.HOME}/Kamome-promo/footage`);
Config.setVideoImageFormat("jpeg");
Config.setCodec("h264");
Config.setCrf(16);
