import { usePlayerState } from "@/states/player";
import React from "preact/compat";
import { FaCompass, FaLocationDot, FaMap } from "react-icons/fa6";
import IconLabelBox from "./ui/icon-label-box";
import { useCompassLocation, useCompassAlways } from "@/states/compass-location";

const Compass = () => {
  const playerState = usePlayerState();
  const compassLocation = useCompassLocation();
  const compassAlways = useCompassAlways();

  if (!compassAlways && !playerState.isInVehicle) {
    return null;
  }
  return (
    <div className={compassLocation === "bottom" ? "flex absolute bottom-1 w-full h-fit items-center justify-center " : "flex w-full h-[10dvh] items-center justify-center"}>
      <div className={"flex gap-3 items-center justify-center w-[50%]"}>
        <IconLabelBox label={playerState.heading} Icon={FaCompass} />
        <IconLabelBox label={playerState.streetLabel} className="min-w-[20%]" Icon={FaLocationDot} />
        <IconLabelBox className="px-3" label={playerState.areaLabel} Icon={FaMap} />
      </div>
    </div>
  );
};

export default React.memo(Compass);

