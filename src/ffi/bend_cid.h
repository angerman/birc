/* Bend 2.0.38 names runtime constructor ids CID_Con and CID_view_OpBox.
 * This FFI still says CID_CON and CID_VIEW_OPBOX. Alias only when the new
 * spelling exists and the old one does not, so the lint stub's own
 * definitions stay in force. */
#ifndef BIRC_BEND_CID_H
#define BIRC_BEND_CID_H

#if !defined(CID_CON) && defined(CID_Con)
#define CID_CON CID_Con
#endif
#if !defined(CID_NIL) && defined(CID_Nil)
#define CID_NIL CID_Nil
#endif
#if !defined(CID_UNIT) && defined(CID_Unit)
#define CID_UNIT CID_Unit
#endif
#if !defined(CID_SOME) && defined(CID_Some)
#define CID_SOME CID_Some
#endif
#if !defined(CID_NONE) && defined(CID_None)
#define CID_NONE CID_None
#endif
#if !defined(CID_SCON) && defined(CID_SCon)
#define CID_SCON CID_SCon
#endif
#if !defined(CID_SNIL) && defined(CID_SNil)
#define CID_SNIL CID_SNil
#endif
#if !defined(CID_VIEW_COL) && defined(CID_view_Col)
#define CID_VIEW_COL CID_view_Col
#endif
#if !defined(CID_VIEW_LNK) && defined(CID_view_Lnk)
#define CID_VIEW_LNK CID_view_Lnk
#endif
#if !defined(CID_VIEW_SPN) && defined(CID_view_Spn)
#define CID_VIEW_SPN CID_view_Spn
#endif
#if !defined(CID_VIEW_OPBOX) && defined(CID_view_OpBox)
#define CID_VIEW_OPBOX CID_view_OpBox
#endif
#if !defined(CID_VIEW_OPSPLIT) && defined(CID_view_OpSplit)
#define CID_VIEW_OPSPLIT CID_view_OpSplit
#endif
#if !defined(CID_VIEW_OPTEXT) && defined(CID_view_OpText)
#define CID_VIEW_OPTEXT CID_view_OpText
#endif
#if !defined(CID_VIEW_OPTABS) && defined(CID_view_OpTabs)
#define CID_VIEW_OPTABS CID_view_OpTabs
#endif
#if !defined(CID_VIEW_OPLINE) && defined(CID_view_OpLine)
#define CID_VIEW_OPLINE CID_view_OpLine
#endif
#if !defined(CID_VIEW_OPIMAGE) && defined(CID_view_OpImage)
#define CID_VIEW_OPIMAGE CID_view_OpImage
#endif
#if !defined(CID_VIEW_OPMEDIA) && defined(CID_view_OpMedia)
#define CID_VIEW_OPMEDIA CID_view_OpMedia
#endif
#if !defined(CID_VIEW_OPGHOST) && defined(CID_view_OpGhost)
#define CID_VIEW_OPGHOST CID_view_OpGhost
#endif

#endif
