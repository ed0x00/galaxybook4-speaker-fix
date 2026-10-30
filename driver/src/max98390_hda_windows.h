/* SPDX-License-Identifier: GPL-2.0 */
//
// MAX98390 HDA: optional Windows-matching init tables
//

#ifndef __MAX98390_HDA_WINDOWS_H
#define __MAX98390_HDA_WINDOWS_H

struct max98390_hda_priv;

int max98390_windows_load(struct max98390_hda_priv *priv);
void max98390_windows_release(struct max98390_hda_priv *priv);
int max98390_windows_init(struct max98390_hda_priv *priv);

#endif /* __MAX98390_HDA_WINDOWS_H */
