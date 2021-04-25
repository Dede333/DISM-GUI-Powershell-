#########################################################################################################################
# Chargement des assemblies externes                                        
#########################################################################################################################
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;

#########################################################################################################################
# Bascule le Script en mode administrateur si celui-ci est un utilisateur standard
# Nous sommes obligé d'être en status administrateur, sinon la commande DISM ne fonctionnera pas !
# Note: L'UAC peut être solicité si celui-ci est activé sur l'hôte !
# Get the ID and security principal of the current user account
# Récupère l'ID et le security principal de l'utilisateur courant
#########################################################################################################################
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent();
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID);

# Get the security principal for the administrator role
# Récupère le security principal pour le rôle administrateur
#
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator;

# Check to see if we are currently running as an administrator
# Regarde si nous sommes déjà en mode administrateur
#
if ($myWindowsPrincipal.IsInRole($adminRole)){
    # We are running as an administrator, so change the title and background colour to indicate this
    # nous sommes déjà en mode administrateur, alors, on change le titre et la couleur de fond pour indiquer cela
    #
    $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)";
    $Host.UI.RawUI.BackgroundColor = "DarkBlue";
    Clear-Host;
}
else{
    # We are not running as an administrator, so relaunch as administrator
    # nous ne sommes pas en administrateur, donc, on relance ce script en mode administrateur
    
    # Create a new process object that starts PowerShell
    # on créé un nouveau objet processus que l'on nomme "PowerShell"
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";

    # Specify the current script path and name as a parameter with added scope and support for scripts with spaces in it's path
    # 
    $newProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'";

    # Indicate that the process should be elevated
    $newProcess.Verb = "runas";
    # Start the new process
    [System.Diagnostics.Process]::Start($newProcess);

    # Exit from the current, unelevated, process
    # sort du script courant (processus utilisateur standard)
    Exit;
}

#########################################################################################################################
# Variables Globales
# Note: il faut ajouter le terme $global:NomVar
#########################################################################################################################

#[String]$StrFolderName;                                           # Nom du dossier de montage du fichier WIM
$global:StrFolderName;                                             # Nom du dossier de montage du fichier WIM 
#[Boolean]$WIMMounted = $false;                                    # état du montage du fichier WIM
$global:WIMMounted = $false;
#[String]$StrMountedImageLocation;                                 # chemin de montage du WIM
$global:StrMountedImageLocation;
#[String]$StrIndex;                                                # index du wim à monter
$global:StrIndex;                                                  # index du wim à monter
#[String]$StrWIM;                                                  # nom du fichier WIM
$global:StrWIM;                                                    # nom du fichier WIM
[String]$StrOutput;                                                # sortie de la console standard (redirigé)
#$global:StrOutput;
[String]$StrDISMExitCode;                                          # valeur de sortie de la commande DISM.EXE
[Boolean]$BlnDISMCommit;                                           # mémorise état changement du fichier WIM monté
#[String]$StrDISMArguments;                                        # argument de la ligne de commande DISM.exe
$global:StrDISMArguments;
[String]$StrProductKey;                                            # Clé d'activation windows
[String]$StrEdition;                                               # type édition produit windows
[String]$StrProductCode;                                           # code produit
[String]$StrPatchCode;                                             # chemin code ?
[String]$StrMSPFileName;                                           # Nom du package de mise à jour
[String]$StrCompression;                                           # mémorise compression WIM

#FormProgress $MaFormeProgress = new FormProgress;                 # Pour instancier la forme FormProgress
#FormAbout MaFormAbout=new FormAbout;                              # pour instancier la forme FormAbout

#########################################################################################################################
# Définition d'une classe pour le stockage des méta-données présentes dans le WIM
#########################################################################################################################
class InfosWIM
{
  [int]$Index_Wim;                                                 # mémorise l'index du WIM
  [string]$Nom_Wim;                                                # mémorise le nom du WIM
  [string]$Description_Wim;                                        # mémorise la description du WIM  
  [uint64]$Taille_Wim;                                             # mémorise la taille du WIM
} 

#########################################################################################################################
$ListInfosWimGestionMontage= New-Object System.Collections.Generic.List[InfosWIM]; # pour le menu Gestion Montage
$ListInfosWimAppliquerImage= New-Object System.Collections.Generic.List[InfosWIM]; # pour le menu Appliquer Image
$ListInfosWimExportImage= New-Object System.Collections.Generic.List[InfosWIM];    # pour le menu Export Image
#########################################################################################################################

#########################################################################################################################
# Function de recherche de la directory en cours du script lancé
#########################################################################################################################
function Get-ScriptDirectory { 
  #Return the directory name of this script
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value; # scope 1 pour l'instance du script ? à vérifier...
  Split-Path $Invocation.MyCommand.Path;                    # récupére le chemin du dossier
}
$ScriptPath = Get-ScriptDirectory;                          # Permet de connaitre le dossier actuel d'où est lancé le script

#########################################################################################################################
# The -STA parameter is required
# Vérifie l'appartenance du THREAD ?, à voir...
#########################################################################################################################
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA ){
   Throw (new-object System.Threading.ThreadStateException("Le script courant nécessite que la session Powershell soit dans le modèle de thread STA (Single Thread Apartment).")) 
}

#########################################################################################################################
# Création des contrôles en mémoires pour la partie graphique
#########################################################################################################################
$FormMain = New-Object System.Windows.Forms.Form;
$menuStrip1 = New-Object System.Windows.Forms.MenuStrip;
$toolStripMenuItem1 = New-Object System.Windows.Forms.ToolStripMenuItem;
$ouvrirLogDISMToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$informationSurLeWIMMontéToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$nettoyerLeWIMToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$nettoyerLimageToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$utiliserLeModeOnlineToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$aProposDeToolStripMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem;
$TabGestion = New-Object System.Windows.Forms.TabControl;
$GestionMontage = New-Object System.Windows.Forms.TabPage;
$TxtBoxTaille = New-Object System.Windows.Forms.TextBox;
$label13 = New-Object System.Windows.Forms.Label;
$TxtBoxDescription = New-Object System.Windows.Forms.TextBox;
$label12 = New-Object System.Windows.Forms.Label;
$TxtBoxNom = New-Object System.Windows.Forms.TextBox;
$label11 = New-Object System.Windows.Forms.Label;
$BtnOuvrirDossierMonte = New-Object System.Windows.Forms.Button;
$BtnDemonterWim = New-Object System.Windows.Forms.Button;
$BtnMonterWim = New-Object System.Windows.Forms.Button;
$LblIndex = New-Object System.Windows.Forms.Label;
$CmbBoxIndex = New-Object System.Windows.Forms.ComboBox;
$chkMountReadOnly = New-Object System.Windows.Forms.CheckBox;
$BtnChoisirDossier = New-Object System.Windows.Forms.Button;
$BtnChoisirWim = New-Object System.Windows.Forms.Button;
$TxtDossierMontage = New-Object System.Windows.Forms.TextBox;
$LblDossierMontage = New-Object System.Windows.Forms.Label;
$LblFichierWim = New-Object System.Windows.Forms.Label;
$TxtFichierWim = New-Object System.Windows.Forms.TextBox;
$GestionPilotes = New-Object System.Windows.Forms.TabPage;
$BtnAfficheTousPilotes = New-Object System.Windows.Forms.Button;
$BtnAffichePilotesWim = New-Object System.Windows.Forms.Button;
$groupBoxSupprimerPilotes = New-Object System.Windows.Forms.GroupBox;
$BtnSupprimePilote = New-Object System.Windows.Forms.Button;
$TxtBoxNomPilote = New-Object System.Windows.Forms.TextBox;
$groupBoxAjouterPilotes = New-Object System.Windows.Forms.GroupBox;
$btnAjouterPilotes = New-Object System.Windows.Forms.Button;
$LblCheminPilote = New-Object System.Windows.Forms.Label;
$BtnChoixDossierPilote = New-Object System.Windows.Forms.Button;
$TxtBoxDossierPilotes = New-Object System.Windows.Forms.TextBox;
$ChkBoxRecurse = New-Object System.Windows.Forms.CheckBox;
$ChkBoxForceUnsigned = New-Object System.Windows.Forms.CheckBox;
$GestionPackage = New-Object System.Windows.Forms.TabPage;
$BtnAffichePackagesWim = New-Object System.Windows.Forms.Button;
$groupBox2 = New-Object System.Windows.Forms.GroupBox;
$BtnSupprimePackageBis = New-Object System.Windows.Forms.Button;
$BtnSupprimePackage = New-Object System.Windows.Forms.Button;
$LblDossierPackagebis = New-Object System.Windows.Forms.Label;
$LblNomPackage = New-Object System.Windows.Forms.Label;
$TxtBoxDossierPackageBis = New-Object System.Windows.Forms.TextBox;
$TxtBoxNomPackage = New-Object System.Windows.Forms.TextBox;
$groupBox1 = New-Object System.Windows.Forms.GroupBox;
$BtnAjoutPackage = New-Object System.Windows.Forms.Button;
$BtnChoisirDossierPackage = New-Object System.Windows.Forms.Button;
$ChkBoxIgnoreVerification = New-Object System.Windows.Forms.CheckBox;
$LblDossierPackage = New-Object System.Windows.Forms.Label;
$TxtBoxDossierPackage = New-Object System.Windows.Forms.TextBox;
$GestionFeature = New-Object System.Windows.Forms.TabPage;
$label4 = New-Object System.Windows.Forms.Label;
$label3 = New-Object System.Windows.Forms.Label;
$label2 = New-Object System.Windows.Forms.Label;
$BtnDisableFeature = New-Object System.Windows.Forms.Button;
$BtnEnableFeature = New-Object System.Windows.Forms.Button;
$BtnAfficheFeatureWim = New-Object System.Windows.Forms.Button;
$ChkBoxEnablePackagePath = New-Object System.Windows.Forms.CheckBox;
$ChkBoxEnablePackageName = New-Object System.Windows.Forms.CheckBox;
$TxtBoxFolderPackage = New-Object System.Windows.Forms.TextBox;
$TxtBoxFeaturePackageName = New-Object System.Windows.Forms.TextBox;
$TxtBoxFeatureName = New-Object System.Windows.Forms.TextBox;
$ServiceEdition = New-Object System.Windows.Forms.TabPage;
$LblEdition = New-Object System.Windows.Forms.Label;
$LblProductKey = New-Object System.Windows.Forms.Label;
$BtnFixeEdition = New-Object System.Windows.Forms.Button;
$BtnFixeCleProduit = New-Object System.Windows.Forms.Button;
$BtnAfficheEditionCible = New-Object System.Windows.Forms.Button;
$BtnAfficheEditionCourante = New-Object System.Windows.Forms.Button;
$TxtBoxEdition = New-Object System.Windows.Forms.TextBox;
$TxtBoxProductKey = New-Object System.Windows.Forms.TextBox;
$ServiceUnattend = New-Object System.Windows.Forms.TabPage;
$BtnAppliqueUnattendXML = New-Object System.Windows.Forms.Button;
$BtnChoisirXMLUnattend = New-Object System.Windows.Forms.Button;
$TxtBoxFichierXMLUnattend = New-Object System.Windows.Forms.TextBox;
$LblFichierXMLUnattend = New-Object System.Windows.Forms.Label;
$ServiceApplication = New-Object System.Windows.Forms.TabPage;
$BtnVerifierPatchsApplication = New-Object System.Windows.Forms.Button;
$LblFichierMSP = New-Object System.Windows.Forms.Label;
$LblPatchCode = New-Object System.Windows.Forms.Label;
$LblCodeProduit = New-Object System.Windows.Forms.Label;
$BtnChoisirFichierMSP = New-Object System.Windows.Forms.Button;
$BtnAfficheInfosPatchsApplications = New-Object System.Windows.Forms.Button;
$BtnAfficheApplicationsPatch = New-Object System.Windows.Forms.Button;
$BtnAfficheInfosApplications = New-Object System.Windows.Forms.Button;
$btnAfficheApplication = New-Object System.Windows.Forms.Button;
$TxtBoxNomFichierMSP = New-Object System.Windows.Forms.TextBox;
$TxtBoxPatchCode = New-Object System.Windows.Forms.TextBox;
$TxtBoxCodeProduit = New-Object System.Windows.Forms.TextBox;
$CaptureImage = New-Object System.Windows.Forms.TabPage;
$label17 = New-Object System.Windows.Forms.Label;
$TxtBoxNomWIM = New-Object System.Windows.Forms.TextBox;
$LblDescriptionWIM = New-Object System.Windows.Forms.Label;
$TxtBoxCaptureDescriptionWIM = New-Object System.Windows.Forms.TextBox;
$ChkBoxCaptureVerifier = New-Object System.Windows.Forms.CheckBox;
$LblCompression = New-Object System.Windows.Forms.Label;
$LblNomFichierWIM = New-Object System.Windows.Forms.Label;
$LblDestination = New-Object System.Windows.Forms.Label;
$LblSource = New-Object System.Windows.Forms.Label;
$CmbBoxCaptureCompression = New-Object System.Windows.Forms.ComboBox;
$TxtBoxNomFichierDest = New-Object System.Windows.Forms.TextBox;
$TxtBoxCaptureDestination = New-Object System.Windows.Forms.TextBox;
$TxtBoxCaptureSource = New-Object System.Windows.Forms.TextBox;
$BtnAjouter = New-Object System.Windows.Forms.Button;
$BtnCreer = New-Object System.Windows.Forms.Button;
$ParcourirDestination = New-Object System.Windows.Forms.Button;
$BtnParcourirSource = New-Object System.Windows.Forms.Button;
$AppliqueImage = New-Object System.Windows.Forms.TabPage;
$TxtBoxAppliquerImageTaille = New-Object System.Windows.Forms.TextBox;
$label14 = New-Object System.Windows.Forms.Label;
$TxtBoxAppliquerImageDescription = New-Object System.Windows.Forms.TextBox;
$label15 = New-Object System.Windows.Forms.Label;
$TxtBoxAppliquerImageNom = New-Object System.Windows.Forms.TextBox;
$label16 = New-Object System.Windows.Forms.Label;
$ChkBoxApplyVerifier = New-Object System.Windows.Forms.CheckBox;
$label5 = New-Object System.Windows.Forms.Label;
$CmbBoxApplyIndex = New-Object System.Windows.Forms.ComboBox;
$LblDestinationBis = New-Object System.Windows.Forms.Label;
$LblSourceBis = New-Object System.Windows.Forms.Label;
$TxtBoxApplyDestination = New-Object System.Windows.Forms.TextBox;
$BtnAppliquerImage = New-Object System.Windows.Forms.Button;
$BtnApplyParcourirDestination = New-Object System.Windows.Forms.Button;
$TxtBoxApplySource = New-Object System.Windows.Forms.TextBox;
$BtnApplyParcourirSource = New-Object System.Windows.Forms.Button;
$ExportImage = New-Object System.Windows.Forms.TabPage;
$TxtBoxExportImageTaille = New-Object System.Windows.Forms.TextBox;
$LblExportImageTaille = New-Object System.Windows.Forms.Label;
$TxtBoxExportImageDescription = New-Object System.Windows.Forms.TextBox;
$LblExportImageDescription = New-Object System.Windows.Forms.Label;
$TxtBoxExportImageNom = New-Object System.Windows.Forms.TextBox;
$LblExportImageNom = New-Object System.Windows.Forms.Label;
$LblExportName = New-Object System.Windows.Forms.Label;
$TxtBoxNomFichier = New-Object System.Windows.Forms.TextBox;
$ChkBoxExportCheckIntegrity = New-Object System.Windows.Forms.CheckBox;
$ChkBoxExportWimBoot = New-Object System.Windows.Forms.CheckBox;
$ChkBoxExportBootable = New-Object System.Windows.Forms.CheckBox;
$label9 = New-Object System.Windows.Forms.Label;
$CmbBoxExportCompression = New-Object System.Windows.Forms.ComboBox;
$label6 = New-Object System.Windows.Forms.Label;
$CmbBoxExportIndex = New-Object System.Windows.Forms.ComboBox;
$LblExportDestination = New-Object System.Windows.Forms.Label;
$LblExportSource = New-Object System.Windows.Forms.Label;
$TxtBoxExportDestination = New-Object System.Windows.Forms.TextBox;
$BtnExportImage = New-Object System.Windows.Forms.Button;
$BtnExportChoisirDossier = New-Object System.Windows.Forms.Button;
$TxtBoxExportSourceFichier = New-Object System.Windows.Forms.TextBox;
$BtnExportChoisirFichier = New-Object System.Windows.Forms.Button;
$GestionLangue = New-Object System.Windows.Forms.TabPage;
$BtnAllIntrlAppliquer = New-Object System.Windows.Forms.Button;
$TxtBoxAllIntl = New-Object System.Windows.Forms.TextBox;
$label7 = New-Object System.Windows.Forms.Label;
$BtnInfosLangue = New-Object System.Windows.Forms.Button;
$ExportDriver = New-Object System.Windows.Forms.TabPage;
$BtnExportDriverOnline = New-Object System.Windows.Forms.Button;
$label8 = New-Object System.Windows.Forms.Label;
$TxtBoxExportDossierDriverOnline = New-Object System.Windows.Forms.TextBox;
$BtnExportDriverChoisirDossierOnline = New-Object System.Windows.Forms.Button;
$BtnExportDriverOffline = New-Object System.Windows.Forms.Button;
$LblExportChoisirDossier = New-Object System.Windows.Forms.Label;
$TxtBoxExportDossierDriverOffline = New-Object System.Windows.Forms.TextBox;
$BtnExportDriverChoisirDossierOffline = New-Object System.Windows.Forms.Button;
$DecoupeImage = New-Object System.Windows.Forms.TabPage;
$BtnDecoupeChoisirFichier = New-Object System.Windows.Forms.Button;
$BtnDecoupeChoisirDossier = New-Object System.Windows.Forms.Button;
$LblDecoupeDossierDestination = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeDossierDestination = New-Object System.Windows.Forms.TextBox;
$btnDecoupeImage = New-Object System.Windows.Forms.Button;
$ChkBoxDecoupeCheckIntegrity = New-Object System.Windows.Forms.CheckBox;
$LblDecoupeTailleFichier = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeTailleFichier = New-Object System.Windows.Forms.TextBox;
$LblDecoupeNomFichierSWM = New-Object System.Windows.Forms.Label;
$LblDecoupeFichierWim = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeFichierSWM = New-Object System.Windows.Forms.TextBox;
$TxtBoxDecoupeFichierWIM = New-Object System.Windows.Forms.TextBox;
$CaptureImageFfu = New-Object System.Windows.Forms.TabPage;
$LblCaptureFfu_Description = New-Object System.Windows.Forms.Label;
$TxtBoxCaptureFfu_Description = New-Object System.Windows.Forms.TextBox;
$LstBoxCaptureFfu_LectLogique = New-Object System.Windows.Forms.ListBox;
$label18 = New-Object System.Windows.Forms.Label;
$LblCaptFfu_Nom = New-Object System.Windows.Forms.Label;
$TxtBoxCaptFfu_Nom = New-Object System.Windows.Forms.TextBox;
$LblCaptFfu_IDPlateforme = New-Object System.Windows.Forms.Label;
$TxtBoxCaptFfu_IDPlateforme = New-Object System.Windows.Forms.TextBox;
$label20 = New-Object System.Windows.Forms.Label;
$LblCaptFfu_NomFichierDest = New-Object System.Windows.Forms.Label;
$LblCaptFfu_DossierDestination = New-Object System.Windows.Forms.Label;
$LblCaptFfu_LecteurPhysique = New-Object System.Windows.Forms.Label;
$CmbBoxCaptureFfu_Compression = New-Object System.Windows.Forms.ComboBox;
$TxtBoxCaptFfu_NomFichierDestination = New-Object System.Windows.Forms.TextBox;
$TxtBoxCaptFfu_DossierDestination = New-Object System.Windows.Forms.TextBox;
$TxtBoxCaptFfu_LecteurPhysique = New-Object System.Windows.Forms.TextBox;
$BtnCaptFfu_Capture = New-Object System.Windows.Forms.Button;
$BtnCaptureFfu_DossierDestination = New-Object System.Windows.Forms.Button;
$BtnCaptureFfu_ChercheLecteurLogique = New-Object System.Windows.Forms.Button;
$AppliqueImageFfu = New-Object System.Windows.Forms.TabPage;
$LstBoxAppliqueImageFfu_LecteurLogique = New-Object System.Windows.Forms.ListBox;
$LblAppliqueImageFfu_LecteurLogique = New-Object System.Windows.Forms.Label;
$label25 = New-Object System.Windows.Forms.Label;
$LblAppliqueImageFfu_FichierSource = New-Object System.Windows.Forms.Label;
$LblAppliqueImageFfu_LecteurPhysique = New-Object System.Windows.Forms.Label;
$TxtBoxAppliqueImageFfu_MotifSFUFile = New-Object System.Windows.Forms.TextBox;
$TxtBoxAppliqueImageFfu_FichierSourceFfu = New-Object System.Windows.Forms.TextBox;
$TxtBoxAppliqueImageFfu_LecteurPhysique = New-Object System.Windows.Forms.TextBox;
$BtnAppliqueImageFfu_AppliqueFfu = New-Object System.Windows.Forms.Button;
$BtnAppliqueImageFfu_ChoisirFichierFfu = New-Object System.Windows.Forms.Button;
$BtnAppliqueImageFfu_ChercherLecteurLogique = New-Object System.Windows.Forms.Button;
$DecoupeFfu = New-Object System.Windows.Forms.TabPage;
$BtnDecoupeFfu_ChoisirFichier = New-Object System.Windows.Forms.Button;
$BtnDecoupeFfu_ChoisirDossier = New-Object System.Windows.Forms.Button;
$LblDecoupeFfu_DossierDestination = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeFfu_DossierDestination = New-Object System.Windows.Forms.TextBox;
$BtnDecoupeFfu_DecoupeImage = New-Object System.Windows.Forms.Button;
$ChkBoxDecoupeFfu_CheckIntegrity = New-Object System.Windows.Forms.CheckBox;
$LblDecoupeFfu_TailleFichier = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeFfu_TailleFichier = New-Object System.Windows.Forms.TextBox;
$LblDecoupeFfu_NomFichierSFUFile = New-Object System.Windows.Forms.Label;
$LblDecoupeFfu_NomFichierFfu = New-Object System.Windows.Forms.Label;
$TxtBoxDecoupeFfu_NomFichierSFU = New-Object System.Windows.Forms.TextBox;
$TxtBoxDecoupeFfu_NomFichierFfu = New-Object System.Windows.Forms.TextBox;
$OpenFileDialogue_ChoisirWIM = New-Object System.Windows.Forms.OpenFileDialog;
$folderBrowserDialog_ChoisirDossier = New-Object System.Windows.Forms.FolderBrowserDialog;
$TxtBoxOutput = New-Object System.Windows.Forms.TextBox;
$label1 = New-Object System.Windows.Forms.Label;
$backgroundWorkerMount = New-Object System.ComponentModel.BackgroundWorker;
$backgroundWorkerDismCommand = New-Object System.ComponentModel.BackgroundWorker;
$backgroundWorkerDismount = New-Object System.ComponentModel.BackgroundWorker;
$BtnEffaceConsoleDism = New-Object System.Windows.Forms.Button;
$OpenFileDialog_ChoisirMSP = New-Object System.Windows.Forms.OpenFileDialog;
$TxtBox_DISMVersion = New-Object System.Windows.Forms.TextBox;
$label10 = New-Object System.Windows.Forms.Label;

#########################################################################################################################
# Définition des objets contrôles graphique, ainsi que les fonctions associées
#########################################################################################################################

#
# menuStrip1
#
$menuStrip1.Items.AddRange(@(
$toolStripMenuItem1))
$menuStrip1.Location = New-Object System.Drawing.Point(0, 0);
$menuStrip1.Name = "menuStrip1";
$menuStrip1.Size = New-Object System.Drawing.Size(903, 29);
$menuStrip1.TabIndex = 0;
$menuStrip1.Text = "menuStrip1";
#
# toolStripMenuItem1
#
$toolStripMenuItem1.DropDownItems.AddRange(@(
$ouvrirLogDISMToolStripMenuItem,
$informationSurLeWIMMontéToolStripMenuItem,
$nettoyerLeWIMToolStripMenuItem,
$nettoyerLimageToolStripMenuItem,
$utiliserLeModeOnlineToolStripMenuItem,
$aProposDeToolStripMenuItem))
$toolStripMenuItem1.Font = New-Object System.Drawing.Font("Segoe UI", 12);
$toolStripMenuItem1.Name = "toolStripMenuItem1";
$toolStripMenuItem1.Size = New-Object System.Drawing.Size(63, 25);
$toolStripMenuItem1.Text = "Outils";
#
# ouvrirLogDISMToolStripMenuItem
#
$ouvrirLogDISMToolStripMenuItem.Name = "ouvrirLogDISMToolStripMenuItem";
$ouvrirLogDISMToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$ouvrirLogDISMToolStripMenuItem.Text = "Ouvrir le journal DISM";

#########################################################################################################################
# Permet d'ouvrir le fichier log de l'outils DISM situé dans le répertoire c:\windows\Logs\DISM\dism.log
#########################################################################################################################

function OnClick_ouvrirLogDISMToolStripMenuItem {
   #[void][System.Windows.Forms.MessageBox]::Show("L'évènement ouvrirLogDISMToolStripMenuItem.Add_Click n'est pas implémenté.");

  $Process = New-Object System.Diagnostics.Process;
  $Process.StartInfo.FileName = "notepad.exe";                              # on utilise l'éditeur notepad de windows
  $process.StartInfo.Arguments="$env:windir\Logs\DISM\dism.log";            # à partir du répertoire environnement windows
  $Process.Start();
  $Process.WaitForExit();
  $Process.Close();
}

$ouvrirLogDISMToolStripMenuItem.Add_Click( { OnClick_ouvrirLogDISMToolStripMenuItem } );

#
# informationSurLeWIMMontéToolStripMenuItem
#
$informationSurLeWIMMontéToolStripMenuItem.Name = "informationSurLeWIMMontéToolStripMenuItem";
$informationSurLeWIMMontéToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$informationSurLeWIMMontéToolStripMenuItem.Text = "Informations  WIMs montés";

#########################################################################################################################
# Permet d'avoir un récapitulatif des WIM montés sur l'hôte
# répertoire de montage, fichier image, index, type R/W et état
#########################################################################################################################

function OnClick_informationSurLeWIMMontéToolStripMenuItem {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement informationSurLeWIMMontéToolStripMenuItem.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Get-MountedImageInfo";
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
  $TxtBoxOutput.Refresh();
  write-host 'OnClick_informationSurLeWIMMontéToolStripMenuItem, valeur actuel de $StrOutput:'$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
  write-host 'OnClick_informationSurLeWIMMontéToolStripMenuItem, valeur après exécution de la commande DISM:'$global:StrOutput;
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
  $TxtBoxOutput.Refresh();
}

$informationSurLeWIMMontéToolStripMenuItem.Add_Click( { OnClick_informationSurLeWIMMontéToolStripMenuItem } );

#
# nettoyerLeWIMToolStripMenuItem
#
$nettoyerLeWIMToolStripMenuItem.Name = "nettoyerLeWIMToolStripMenuItem";
$nettoyerLeWIMToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$nettoyerLeWIMToolStripMenuItem.Text = "Nettoyer le WIM";

#########################################################################################################################
# Permet de nettoyer les WIMs (fichiers périmés sur chaque lecteur)
#########################################################################################################################

function OnClick_nettoyerLeWIMToolStripMenuItem {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement nettoyerLeWIMToolStripMenuItem.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Cleanup-WIM";
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
  $TxtBoxOutput.Refresh();
  write-host 'OnClick_nettoyerLeWIMToolStripMenuItem, valeur actuel de $StrOutput:'$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
  write-host 'OnClick_nettoyerLeWIMToolStripMenuItem, valeur après exécution de la commande DISM:'$global:StrOutput;
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
  $TxtBoxOutput.Refresh();
}

$nettoyerLeWIMToolStripMenuItem.Add_Click( { OnClick_nettoyerLeWIMToolStripMenuItem } );

#
# nettoyerLimageToolStripMenuItem
#
$nettoyerLimageToolStripMenuItem.Name = "nettoyerLimageToolStripMenuItem";
$nettoyerLimageToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$nettoyerLimageToolStripMenuItem.Text = "Nettoyer l'image";

#########################################################################################################################
# Permet de nettoyer les WIMs (fichiers périmés sur chaque lecteur)
#########################################################################################################################

function OnClick_nettoyerLimageToolStripMenuItem {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement nettoyerLimageToolStripMenuItem.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Cleanup-Image /RevertPendingActions";
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
  $TxtBoxOutput.Refresh();
  write-host 'OnClick_nettoyerLimageToolStripMenuItem, valeur actuel de $StrOutput:'$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
  write-host 'OnClick_nettoyerLimageToolStripMenuItem, valeur après exécution de la commande DISM:'$global:StrOutput;
  $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
  $TxtBoxOutput.Refresh();
}

$nettoyerLimageToolStripMenuItem.Add_Click( { OnClick_nettoyerLimageToolStripMenuItem } );

#
# utiliserLeModeOnlineToolStripMenuItem
#
$utiliserLeModeOnlineToolStripMenuItem.Name = "utiliserLeModeOnlineToolStripMenuItem";
$utiliserLeModeOnlineToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$utiliserLeModeOnlineToolStripMenuItem.Text = "Utiliser le mode Online";

function OnClick_utiliserLeModeOnlineToolStripMenuItem {
	[void][System.Windows.Forms.MessageBox]::Show("L'évènement utiliserLeModeOnlineToolStripMenuItem.Add_Click n'est pas implémenté.");
}

$utiliserLeModeOnlineToolStripMenuItem.Add_Click( { OnClick_utiliserLeModeOnlineToolStripMenuItem } );

#
# aProposDeToolStripMenuItem
#
$aProposDeToolStripMenuItem.Name = "aProposDeToolStripMenuItem";
$aProposDeToolStripMenuItem.Size = New-Object System.Drawing.Size(273, 26);
$aProposDeToolStripMenuItem.Text = "A propos de";

function OnClick_aProposDeToolStripMenuItem {
	[void][System.Windows.Forms.MessageBox]::Show("L'évènement aProposDeToolStripMenuItem.Add_Click n'est pas implémenté.");
}

$aProposDeToolStripMenuItem.Add_Click( { OnClick_aProposDeToolStripMenuItem } );

#
# TabGestion
#
$TabGestion.Controls.Add($GestionMontage);
$TabGestion.Controls.Add($GestionPilotes);
$TabGestion.Controls.Add($GestionPackage);
$TabGestion.Controls.Add($GestionFeature);
$TabGestion.Controls.Add($ServiceEdition);
$TabGestion.Controls.Add($ServiceUnattend);
$TabGestion.Controls.Add($ServiceApplication);
$TabGestion.Controls.Add($CaptureImage);
$TabGestion.Controls.Add($AppliqueImage);
$TabGestion.Controls.Add($ExportImage);
$TabGestion.Controls.Add($GestionLangue);
$TabGestion.Controls.Add($ExportDriver);
$TabGestion.Controls.Add($DecoupeImage);
$TabGestion.Controls.Add($CaptureImageFfu);
$TabGestion.Controls.Add($AppliqueImageFfu);
$TabGestion.Controls.Add($DecoupeFfu);
$TabGestion.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$TabGestion.Location = New-Object System.Drawing.Point(0, 27);
$TabGestion.Name = "TabGestion";
$TabGestion.SelectedIndex = 0;
$TabGestion.Size = New-Object System.Drawing.Size(890, 290);
$TabGestion.TabIndex = 1;
#
# GestionMontage
#
$GestionMontage.Controls.Add($TxtBoxTaille);
$GestionMontage.Controls.Add($label13);
$GestionMontage.Controls.Add($TxtBoxDescription);
$GestionMontage.Controls.Add($label12);
$GestionMontage.Controls.Add($TxtBoxNom);
$GestionMontage.Controls.Add($label11);
$GestionMontage.Controls.Add($BtnOuvrirDossierMonte);
$GestionMontage.Controls.Add($BtnDemonterWim);
$GestionMontage.Controls.Add($BtnMonterWim);
$GestionMontage.Controls.Add($LblIndex);
$GestionMontage.Controls.Add($CmbBoxIndex);
$GestionMontage.Controls.Add($chkMountReadOnly);
$GestionMontage.Controls.Add($BtnChoisirDossier);
$GestionMontage.Controls.Add($BtnChoisirWim);
$GestionMontage.Controls.Add($TxtDossierMontage);
$GestionMontage.Controls.Add($LblDossierMontage);
$GestionMontage.Controls.Add($LblFichierWim);
$GestionMontage.Controls.Add($TxtFichierWim);
$GestionMontage.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$GestionMontage.Location = New-Object System.Drawing.Point(4, 29);
$GestionMontage.Name = "GestionMontage";
$GestionMontage.Padding = New-Object System.Windows.Forms.Padding(3);
$GestionMontage.Size = New-Object System.Drawing.Size(882, 257);
$GestionMontage.TabIndex = 0;
$GestionMontage.Text = "Gestion Montage";
$GestionMontage.UseVisualStyleBackColor = $true;
#
# TxtBoxTaille
#
$TxtBoxTaille.Enabled = $false;
$TxtBoxTaille.Location = New-Object System.Drawing.Point(148, 178);
$TxtBoxTaille.Name = "TxtBoxTaille";
$TxtBoxTaille.Size = New-Object System.Drawing.Size(475, 26);
$TxtBoxTaille.TabIndex = 20;
#
# label13
#
$label13.AutoSize = $true;
$label13.Location = New-Object System.Drawing.Point(11, 178);
$label13.Name = "label13";
$label13.Size = New-Object System.Drawing.Size(49, 20);
$label13.TabIndex = 19;
$label13.Text = "Taille:";
#
# TxtBoxDescription
#
$TxtBoxDescription.Enabled = $false;
$TxtBoxDescription.Location = New-Object System.Drawing.Point(148, 146);
$TxtBoxDescription.Name = "TxtBoxDescription";
$TxtBoxDescription.Size = New-Object System.Drawing.Size(475, 26);
$TxtBoxDescription.TabIndex = 18;
#
# label12
#
$label12.AutoSize = $true;
$label12.Location = New-Object System.Drawing.Point(11, 149);
$label12.Name = "label12";
$label12.Size = New-Object System.Drawing.Size(93, 20);
$label12.TabIndex = 17;
$label12.Text = "Description:";
#
# TxtBoxNom
#
$TxtBoxNom.Enabled = $false;
$TxtBoxNom.Location = New-Object System.Drawing.Point(148, 114);
$TxtBoxNom.Name = "TxtBoxNom";
$TxtBoxNom.Size = New-Object System.Drawing.Size(475, 26);
$TxtBoxNom.TabIndex = 16;
#
# label11
#
$label11.AutoSize = $true;
$label11.Location = New-Object System.Drawing.Point(11, 117);
$label11.Name = "label11";
$label11.Size = New-Object System.Drawing.Size(46, 20);
$label11.TabIndex = 15;
$label11.Text = "Nom:";
#
# BtnOuvrirDossierMonte
#
$BtnOuvrirDossierMonte.Location = New-Object System.Drawing.Point(680, 158);
$BtnOuvrirDossierMonte.Name = "BtnOuvrirDossierMonte";
$BtnOuvrirDossierMonte.Size = New-Object System.Drawing.Size(168, 45);
$BtnOuvrirDossierMonte.TabIndex = 14;
$BtnOuvrirDossierMonte.Text = "Ouvrir dossier monté";
$BtnOuvrirDossierMonte.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de visualiser le contenu du dossier point de montage du WIM
###########################################################################################################################
function OnClick_BtnOuvrirDossierMonte {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnOuvrirDossierMonte.Add_Click n'est pas implémenté.");
  
  $Process = New-Object System.Diagnostics.Process;
  $Process.StartInfo.FileName = "explorer.exe";                           # on utilise l'explorer de windows
  $process.StartInfo.Arguments=$global:StrFolderName;                     # sur le dossier (point de montage) du wim monté
  $Process.Start();
  $Process.WaitForExit();
  $Process.Close();
}

$BtnOuvrirDossierMonte.Add_Click( { OnClick_BtnOuvrirDossierMonte } );

#
# BtnDemonterWim
#
$BtnDemonterWim.Enabled = $true;
$BtnDemonterWim.Location = New-Object System.Drawing.Point(680, 96);
$BtnDemonterWim.Name = "BtnDemonterWim";
$BtnDemonterWim.Size = New-Object System.Drawing.Size(168, 46);
$BtnDemonterWim.TabIndex = 13;
$BtnDemonterWim.Text = "Démonter WIM";
$BtnDemonterWim.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de démonter un WIM en fonction de son point de montage (celui-ci à était mémorisé lors du montage)
# Attention: On ne peut monter qu'une seule et une seule image à la fois !!
###########################################################################################################################

function OnClick_BtnDemonterWim {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDemonterWim.Add_Click n'est pas implémenté.");
  
  $TxtBoxOutput.Text="";                                       # Efface le contenu de la console gui  
  $global:StrOutput = "";                                      # Efface le contenu de la mémoire console

  $result = [System.Windows.Forms.MessageBox]::Show("Voulez-vous appliquer les changements ?", "WIM monté" , 4);
  if ($Result -eq "Yes"){
    $BlnDISMCommit=$true;                                      # option /commit
  }
  else{
    $BlnDismCommit=$false;                                     # option /discard
  }
  write-host("Onclick_BtnDemonterWim, Début du démontage du Wim...");
  write-host 'Onclick_BtnDemonterWim, valeur de la variable $global:StrFolderName:'$global:StrFolderName;
  write-host 'Onclick_BtnDemonterWim, valeur de la variable $global:BlnDismCommit:'$BlnDismCommit;
  $StrDISMExitCode = "";
  $Process = New-Object System.Diagnostics.Process;           # nouveau processus pour la commande DISM
  $Process.StartInfo.StandardOutputEncoding= [System.Text.Encoding]::GetEncoding($Host.CurrentCulture.TextInfo.OEMCodePage);
  $Process.StartInfo.RedirectStandardOutput = $true;          # Redirection standard de la console
  $Process.StartInfo.RedirectStandardError = $true; 		  # Idem pour le canal d'erreur
  $Process.StartInfo.UseShellExecute = $false;				  # processus sans shell
  $Process.StartInfo.CreateNoWindow = $true;					  # pas de fenêtre console pour ce processus
  $Process.StartInfo.FileName = "DISM.EXE";
  if ($BlnDismCommit -eq $true){           					  # gestion du flag /Commit or /Discard (DISM)
    $Process.StartInfo.Arguments = "/UnMount-Wim /MountDir:`"$global:StrFolderName`" /Commit";  # /Commit
  }
  else{
    $Process.StartInfo.Arguments = "/UnMount-Wim /MountDir:`"$global:StrFolderName`" /Discard";  # /Discard
  }
  Write-host "Exécution de la ligne de commande: DISM.EXE "$Process.StartInfo.Arguments.ToString();
  $global:StrOutput = "Exécution de la ligne de commande: DISM.EXE "+$Process.StartInfo.Arguments.ToString();
  $TxtBoxOutput.Text=$global:StrOutput;
  $TxtBoxOutput.Refresh();
  $Process.Start() | Out-Null;                          # Out-Null évite le retour de True sur la console
  #write-host $Process.StandardOutput.ReadToEnd();      # affichage dans console ou dans forme, mais pas les deux en même temps
  $global:StrOutput=$global:StrOutput+$Process.StandardOutput.ReadToEnd();
  $Process.WaitForExit();							   # attend la fin du processus
  $TxtBoxOutput.Text=$global:StrOutput;
  $TxtBoxOutput.Refresh();
  write-host 'Onclick_BtnDemonterWim, Valeur de retour de $Process.ExitCode:'$Process.ExitCode;
  if ($Process.ExitCode -eq 0){
    $global:WIMMounted=$false;                         # le fichier wim est démonté
    $global:StrMountedImageLocation="";                # fixe chemin du point de montage wim à la valeur vide
    $BtnMonterWim.Enabled=$true;                       # désactive le bouton BtnMounterWim (1 seul Wim à la fois)
    $BtnDemonterWim.Enabled=$true;                     # active le bouton BtnDemonterWim
  }
  else{
    $global:WIMMounted=$false;                         # le wim n'est pas monté
  }
  write-host("Onclick_BtnDemonterWim, Fin du démontage du Wim...");
  $Process.Close();									   # referme le processus
}

$BtnDemonterWim.Add_Click( { OnClick_BtnDemonterWim } );

#
# BtnMonterWim
#
$BtnMonterWim.Location = New-Object System.Drawing.Point(680, 19);
$BtnMonterWim.Name = "BtnMonterWim";
$BtnMonterWim.Size = New-Object System.Drawing.Size(168, 45);
$BtnMonterWim.TabIndex = 12;
$BtnMonterWim.Text = "Monter Wim";
$BtnMonterWim.UseVisualStyleBackColor = $true;

#########################################################################################################################
# Permet de monter un fichier WIM en fonction de l'index sélectionné et du point de montage
#
#########################################################################################################################

function OnClick_BtnMonterWim {
#	[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnMonterWim.Add_Click n'est pas implémenté.");
  
  $global:StrFolderName = $TxtDossierMontage.Text;                           # mémorise dossier montage
  $global:StrIndex = $CmbBoxIndex.Text;                                      # idem pour l'index
  $global:StrWIM = $TxtFichierWim.Text;                                      # idem pour le nom du WIM
  $global:StrOutput = ""                                                     # Efface le contenu

  write-host("OnClick_BtnMonterWim, Début du montage du Wim...");            # petit message dans powershell (début de la fonction montage du wim)
  write-host 'Onclick_BtnMonterWim, valeur de la variable $global:StrFolderName:'$global:StrFolderName;# affiche les variables globales
  write-host 'Onclick_BtnMonterWim, valeur de la variable $global:StrIndex:'$global:StrIndex;
  write-host 'Onclick_BtnMonterWim, valeur de la variable $global:StrWIM:'$global:StrWIM;

  $StrDISMExitCode = "";
  $Process = New-Object System.Diagnostics.Process; 
  $Process.StartInfo.StandardOutputEncoding= [System.Text.Encoding]::GetEncoding($Host.CurrentCulture.TextInfo.OEMCodePage);
  $Process.StartInfo.RedirectStandardOutput = $true;
  $Process.StartInfo.RedirectStandardError = $true;
  $Process.StartInfo.UseShellExecute = $false;
  $Process.StartInfo.CreateNoWindow = $true;
  $Process.StartInfo.FileName = "DISM.EXE";
  if ($chkMountReadOnly.Checked -eq $true){             # gestion du flag lecture seule /ReadOnly (DISM)
    $Process.StartInfo.Arguments = "/Mount-Wim /WimFile:`"$global:StrWIM`" /Index:$global:StrIndex /MountDir:`"$global:StrFolderName`" /ReadOnly";
  }
  else{
    $Process.StartInfo.Arguments = "/Mount-Wim /WimFile:`"$global:StrWIM`" /Index:$global:StrIndex /MountDir:`"$global:StrFolderName`"";
  }
  Write-host "OnClick_BtnMonterWim, Exécution de la ligne de commande: DISM.EXE "$Process.StartInfo.Arguments.ToString();
  $global:StrOutput = "Exécution de la ligne de commande: DISM.EXE "+$Process.StartInfo.Arguments.ToString();
  $TxtBoxOutput.Text=$global:StrOutput;
  $TxtBoxOutput.Refresh();
  $Process.Start() | Out-Null;                        # Out-Null évite le retour de True sur la console
  #write-host $Process.StandardOutput.ReadToEnd();    # permet l'affichage des infos dans la console powershell
  $global:StrOutput=$global:StrOutput+$Process.StandardOutput.ReadToEnd(); # permet l'affichage au niveau de la partie graphique
  $Process.WaitForExit();                             # attends la fin du processus
  $TxtBoxOutput.Text=$global:StrOutput;               # mise à jour du contenu du contrôle (console text dans forme graphique)
  $TxtBoxOutput.Refresh();                            # on rafraichit le contrôle
  write-host 'Onclick_BtnMonterWim, Valeur de retour de $Process.ExitCode:'$Process.ExitCode;
  if ($Process.ExitCode -eq 0){
    $global:WIMMounted=$true;                         # le fichier wim est monté
    $global:StrMountedImageLocation=$TxtDossierMontage.Text; # mémorise chemin point de montage
    $BtnMonterWim.Enabled=$false;                     # désactive le bouton BtnMounterWim (1 seul Wim à la fois)
    $BtnDemonterWim.Enabled=$true;                    # active le bouton BtnDemonterWim
  }
  else{
    $global:WIMMounted=$false;                        # le wim n'est pas monté
  }
  write-host("OnClick_BtnMonterWim, Fin du montage du Wim...");  # petit message fin de montage du wim dans powershell
  $Process.Close();                                   # referme le processus
}

$BtnMonterWim.Add_Click( { OnClick_BtnMonterWim } );

#
# LblIndex
#
$LblIndex.AutoSize = $true;
$LblIndex.Location = New-Object System.Drawing.Point(575, 3);
$LblIndex.Name = "LblIndex";
$LblIndex.Size = New-Object System.Drawing.Size(48, 20);
$LblIndex.TabIndex = 11;
$LblIndex.Text = "Index";
#
# CmbBoxIndex
#
$CmbBoxIndex.FormattingEnabled = $true;
$CmbBoxIndex.Location = New-Object System.Drawing.Point(579, 28);
$CmbBoxIndex.Name = "CmbBoxIndex";
$CmbBoxIndex.Size = New-Object System.Drawing.Size(45, 28);
$CmbBoxIndex.TabIndex = 10;

#########################################################################################################################
# Mise à jour des informations concernant le WIM dans la forme principale en fonction de l'index sélectionné
#########################################################################################################################

function OnSelectedIndexChanged_CmbBoxIndex {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement CmbBoxIndex.Add_SelectedIndexChanged n'est pas implémenté.");
  
  write-host "CmbBoxIndex, l'index sélectionner est: "$CmbBoxIndex.selectedIndex;
  
  $TxtBoxNom.Text = $ListInfosWimGestionMontage[$CmbBoxIndex.selectedIndex].Nom_Wim;
  $TxtBoxDescription.Text = $ListInfosWimGestionMontage[$CmbBoxIndex.selectedIndex].Description_Wim;
  $TxtBoxTaille.Text = $ListInfosWimGestionMontage[$CmbBoxIndex.selectedIndex].Taille_Wim;
}

$CmbBoxIndex.Add_SelectedIndexChanged( { OnSelectedIndexChanged_CmbBoxIndex } );

#
# chkMountReadOnly
#
$chkMountReadOnly.AutoSize = $true;
$chkMountReadOnly.Location = New-Object System.Drawing.Point(550, 71);
$chkMountReadOnly.Name = "chkMountReadOnly";
$chkMountReadOnly.Size = New-Object System.Drawing.Size(124, 24);
$chkMountReadOnly.TabIndex = 9;
$chkMountReadOnly.Text = "Lecture seule";
$chkMountReadOnly.UseVisualStyleBackColor = $true;
#
# BtnChoisirDossier
#
$BtnChoisirDossier.Location = New-Object System.Drawing.Point(410, 69);
$BtnChoisirDossier.Name = "BtnChoisirDossier";
$BtnChoisirDossier.Size = New-Object System.Drawing.Size(125, 26);
$BtnChoisirDossier.TabIndex = 7;
$BtnChoisirDossier.Text = "Choisir Dossier";
$BtnChoisirDossier.UseVisualStyleBackColor = $true;

#########################################################################################################################
# Permet de choisir un dossier pour le point de montage
# Révision: 26/12/2020
#########################################################################################################################

function OnClick_BtnChoisirDossier {
	# [void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoisirDossier.Add_Click n'est pas implémenté.");
    
    # définit un objet FolderBrowser
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
      RootFolder='MyComputer'
      SelectedPath = 'C:\'                                    # à partir du dossier c:\
    }
 
    [void]$FolderBrowser.ShowDialog();                        # Affiche l'objet FolderBrowser boite de dialogue
    $TxtDossierMontage.Text=$FolderBrowser.SelectedPath;      # récupère la sélection de l'utilisateur
}

$BtnChoisirDossier.Add_Click( { OnClick_BtnChoisirDossier } );# gestion de l'évènement sur clic bouton BtnChoisirDossier

#
# BtnChoisirWim
#
$BtnChoisirWim.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$BtnChoisirWim.Location = New-Object System.Drawing.Point(410, 28);
$BtnChoisirWim.Name = "BtnChoisirWim";
$BtnChoisirWim.Size = New-Object System.Drawing.Size(125, 26);
$BtnChoisirWim.TabIndex = 6;
$BtnChoisirWim.Text = "Choisir WIM";
$BtnChoisirWim.UseVisualStyleBackColor = $true;

#########################################################################################################################
# Fonction AfficheWimInfos
# Permet d'obtenir les informations concernant le wim: nombre index, nom, description, taille
#########################################################################################################################

function AfficheWimInfos([String]$NomFichier,[String]$NomFichierWim) {
    
  $StrWIM=$NomFichierWim;                                                # mise à jour de la variable globale (nom fichier WIM)
  $StrDISMArguments = "/Get-WimInfo /WimFile:`"$NomFichierWim`"";        # ligne de commande passé à la fonction DISM
  write-host 'Dans AfficheWimInfos, la variable $NomFichier à pour valeur:'$NomFichier;
  write-host 'Dans AfficheWimInfos, la variable $NomFichierWim à pour valeur:'$NomFichierWim;
  write-host "Dans AfficheWimInfos, Exécution de la ligne de commande: DISM.EXE $StrDISMArguments";
  
  #$TxtBoxOutput.Text="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";# pour infos utilisateur message sysntaxe de la commande DISM
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  write-host 'Dans AfficheWimInfos, valeur actuel de $StrOutput:'$global:StrOutput;
  
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
  $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
  $TxtBoxOutput.Refresh();
  try{                                                                   # sauvegarde sur disque dans le dossier en cours du résultat
    $sw = New-Object System.IO.StreamWriter($NomFichier);                # dans le dossier c:\windows\system32 à corriger
    $sw.WriteLine($StrOutput);
    $sw.Close();
  }
  catch{
    [void][System.Windows.Forms.MessageBox]::Show("Dans AfficheWimInfos, Erreur lors de la création du fichier (wiminfos.txt):"+$_);
  } 
}

#########################################################################################################################
# Lecture des informations sur le WIM depuis le fichier wiminfos (du dossier de l'application)
# Révision 11/11/2020
# Nom fichier est la représentation des index sauvegardé sur disk dur
# résultat de la commande DISM /Get-WimInfo
# List<InfosWIM> ListInfosWim, tableau fortement typé qui contient les infos WIMs
#########################################################################################################################
#
function MAJListeIndex([String]$NomFichier, [System.Collections.Generic.List[InfosWIM]]$ListInfosWim) {

   [string]$FileName = $NomFichier;                              # présent dans le dossier de l'application
   [string]$LigneFic = "";                                       # mémorise une ligne
   [string]$StrSansEspace = "";
   [int]$IdxDebStr;
   [string]$TailleWIm=[string]::Empty;                           # stockage temporaire taille wim sous forme caractères

   write-host "MAJListeIndex, Nom du fichier passé en paramètre: $NomFichier";

   # nom de fichier par rapport au menu dans l'application DISM-GUI
   $r = New-Object System.IO.StreamReader($FileName);            # déclaration objet StreamReader
   $ListInfosWim.Clear();                                        # efface le contenu de la liste
            
   try
   {
      while ($r.EndOfStream -ne $true){                          # tend que pas fin de fichier
        $IdxDebStr = 0;                                          # Index de début de chaine à analyser
        $LigneFic = $r.ReadLine();                               # lecture d'une ligne flux StreamReader
        write-host "Dans MAJListeIndex, valeur de la ligne: "$LigneFic;
        #pause
        $IdxDebStr = $LigneFic.IndexOf("Index");                 # recherche chaine "Index :"
        if ($IdxDebStr -eq 0){                                   # chaine trouvé si 0 sinon -1
          $UnWim=[InfosWIM]::new();                             # nouvelle instance de InfosWim (class)
          $UnWim.Index_Wim = [System.int32]($LigneFic.Substring($IdxDebStr + 8, ($LigneFic.Length) - 8));
          $LigneFic = $r.ReadLine();                             # lecture nom wim
          $UnWim.Nom_Wim = $LigneFic.Substring(6, ($LigneFic.Length) - 6);
          write-host 'Dans MAJListeIndex, valeur de la variable $UnWim.Nom_Wim:'$UnWim.Nom_Wim;
          $LigneFic = $r.ReadLine();                             # lecture description
          $UnWim.Description_Wim = $LigneFic.Substring(14, ($LigneFic.Length) - 14);
          write-host 'Dans MAJListeIndex, valeur de la variable $UnWim.Description_Wim:'$UnWim.Description_Wim;
          $LigneFic = $r.ReadLine();                             # lecture taille wim
          write-host 'Dans MAJListeIndex, valeur de $LigneFic: '$LigneFic;
          write-host 'Dans MAJListeIndex, taille de la chaine variable $LigneFic: '$LigneFic.length;
          #$StrSansEspace = $LigneFic -Replace 0x3F, ""         # supprime les espaces en UTF8
          #$bidule = $LigneFic.replace(0x20,"")
          for ($IdxCar=0; $IdxCar -lt $LigneFic.Length; $IdxCar++)
          {
            if ([Char]::IsDigit($LigneFic[$IdxCar])){
              $TailleWim += $LigneFic[$IdxCar];
            }
          }
          write-host 'Dans MAJListeIndex, valeur de $TailleWim: '$TailleWim;
          $UnWim.Taille_Wim=[System.Uint64]$TailleWim;
          #$UnWim.Taille_Wim = [System.Uint64]($StrSansEspace.Substring(8, ($StrSansEspace.Length) - 15));# problème à résoudre
          $ListInfosWim.Add($UnWim);
          $TailleWim="";                                          # Remise à zéro du tampon mémorise la taille d'un wim
        }
      }
      $r.Close();                                                 # referme le fichier
   }
   catch{
     [void][System.Windows.Forms.MessageBox]::Show("Dans MAJListeIndex, Erreur de lecture du fichier: " + $_);
   }
 }

#########################################################################################################################
# Permet de choisir le fichier WIM ou ESD 
# Note: On ne peut pas directement monter un fichier ESD, donc attention !!
# Révision: 26/12/2020
#########################################################################################################################

function OnClick_BtnChoisirWim {
  #[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoisirWim.Add_Click n'est pas implémenté.");
  
  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    Filter = 'Image Wim (*.wim)|*.wim|Image ESD (*.esd)|*.esd'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtFichierWim.Text=$FileBrowser.FileName;      # Affiche le résultat de la sélection dans le champ TxtFichierWim
  }
  
  if ($TxtFichierWim.Text -eq ""){
     [System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier WIM en premier.", "Information WIM", [System.Windows.Forms.MessageBoxButtons]::OK);
  }
  else{                                    # nom de fichier qui sera stocké dans le répertoire de l'application DISM-GUI
      write-host "Dans OnClick_BtnChoisirWim, Avant Appel de AfficheWimInfos: "$TxtFichierWim.Text;
      AfficheWimInfos "GestionMontage_WimInfos.txt" $TxtFichierWim.Text;         # On passe les deux arguments 
      $CmbBoxIndex.Items.Clear();                                                # efface le contenu de la combobox d'index
      write-host 'Dans OnClick_BtnChoisirWim, Type de la variable $ListInfosWimGestionMontage: '$ListInfosWimGestionMontage.gettype();
      MAJListeIndex "GestionMontage_WimInfos.txt" $ListInfosWimGestionMontage;   # Mise à jour des index
              
      for ($IdxFor = 1; $IdxFor -le $ListInfosWimGestionMontage.Count; $IdxFor++){
         $CmbBoxIndex.Items.Add($IdxFor);                                        # création interval index concernant le WIM
      }
   }
}

$BtnChoisirWim.Add_Click( { OnClick_BtnChoisirWim } ); # gestion de l'évènement sur clic bouton BtnChoisirWim

#
# TxtDossierMontage
#
$TxtDossierMontage.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$TxtDossierMontage.Location = New-Object System.Drawing.Point(148, 69);
$TxtDossierMontage.Name = "TxtDossierMontage";
$TxtDossierMontage.Size = New-Object System.Drawing.Size(256, 26);
$TxtDossierMontage.TabIndex = 5;
#
# LblDossierMontage
#
$LblDossierMontage.AutoSize = $true;
$LblDossierMontage.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$LblDossierMontage.Location = New-Object System.Drawing.Point(8, 75);
$LblDossierMontage.Name = "LblDossierMontage";
$LblDossierMontage.Size = New-Object System.Drawing.Size(134, 20);
$LblDossierMontage.TabIndex = 4;
$LblDossierMontage.Text = "Dossier Montage:";
#
# LblFichierWim
#
$LblFichierWim.AutoSize = $true;
$LblFichierWim.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$LblFichierWim.Location = New-Object System.Drawing.Point(11, 31);
$LblFichierWim.Name = "LblFichierWim";
$LblFichierWim.Size = New-Object System.Drawing.Size(95, 20);
$LblFichierWim.TabIndex = 3;
$LblFichierWim.Text = "Fichier Wim:";
#
# TxtFichierWim
#
$TxtFichierWim.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$TxtFichierWim.Location = New-Object System.Drawing.Point(148, 28);
$TxtFichierWim.Name = "TxtFichierWim";
$TxtFichierWim.Size = New-Object System.Drawing.Size(256, 26);
$TxtFichierWim.TabIndex = 2;
#
# GestionPilotes
#
$GestionPilotes.Controls.Add($BtnAfficheTousPilotes);
$GestionPilotes.Controls.Add($BtnAffichePilotesWim);
$GestionPilotes.Controls.Add($groupBoxSupprimerPilotes);
$GestionPilotes.Controls.Add($groupBoxAjouterPilotes);
$GestionPilotes.Location = New-Object System.Drawing.Point(4, 29);
$GestionPilotes.Name = "GestionPilotes";
$GestionPilotes.Padding = New-Object System.Windows.Forms.Padding(3);
$GestionPilotes.Size = New-Object System.Drawing.Size(882, 257);
$GestionPilotes.TabIndex = 1;
$GestionPilotes.Text = "Gestion des drivers";
$GestionPilotes.UseVisualStyleBackColor = $true;
#
# BtnAfficheTousPilotes
#
$BtnAfficheTousPilotes.Location = New-Object System.Drawing.Point(678, 107);
$BtnAfficheTousPilotes.Name = "BtnAfficheTousPilotes";
$BtnAfficheTousPilotes.Size = New-Object System.Drawing.Size(172, 77);
$BtnAfficheTousPilotes.TabIndex = 6;
$BtnAfficheTousPilotes.Text = "Affiche tous les pilotes présent dans le WIM";
$BtnAfficheTousPilotes.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher tous les pilotes présent dans un wim
###########################################################################################################################

function OnClick_BtnAfficheTousPilotes {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheTousPilotes.Add_Click n'est pas implémenté.");

  if ($global:WIMMounted -eq $false){                                       # Aucun WIM monté
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{                                                                     # Fichier WIM monté
     write-host "Dans OnClick_BtnAfficheTousPilotes, Register-ObjectEvent pour $BackgroundWorkerDismCommand effectué";
     write-host 'Dans OnClick_BtnAfficheTousPilotes, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:`"$global:StrMountedImageLocation`" /Get-Drivers /All";  # ré-utilise la variable (globale StrMountedImageLocation)
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     write-host 'Dans OnClick_BtnAfficheTousPilotes, valeur avant de $global:StrOutput:'$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
     $TxtBoxOutput.Refresh();
     write-host 'Dans OnClick_BtnAfficheTousPilotes, valeur de la variable $StrDISMArguments:'$StrDISMArguments;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host 'Dans OnClick_BtnAfficheTousPilotes, valeur après de $global:StrOutput:'$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
     $TxtBoxOutput.Refresh();
  }
 }

$BtnAfficheTousPilotes.Add_Click( { OnClick_BtnAfficheTousPilotes } );

#
# BtnAffichePilotesWim
#
$BtnAffichePilotesWim.Location = New-Object System.Drawing.Point(678, 6);
$BtnAffichePilotesWim.Name = "BtnAffichePilotesWim";
$BtnAffichePilotesWim.Size = New-Object System.Drawing.Size(172, 82);
$BtnAffichePilotesWim.TabIndex = 5;
$BtnAffichePilotesWim.Text = "Affiche les pilotes tiers présent dans le WIM";
$BtnAffichePilotesWim.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les pilotes présent dans un wim
###########################################################################################################################

function OnClick_BtnAffichePilotesWim {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAffichePilotesWim.Add_Click n'est pas implémenté.");

   if ($global:WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
     write-host 'Dans OnClick_BtnAffichePilotesWim, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:`"$global:StrMountedImageLocation`" /Get-Drivers";  # ré-utilise la variable (globale StrMountedImageLocation)
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     write-host 'Dans OnClick_BtnAffichePilotesWim, valeur actuel de $StrOutput:'$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
     $TxtBoxOutput.Refresh();
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host 'Dans OnClick_BtnAffichePilotesWim, valeur après exécution de la commande DISM:'$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
     $TxtBoxOutput.Refresh();
    }
}

$BtnAffichePilotesWim.Add_Click( { OnClick_BtnAffichePilotesWim } );

#
# groupBoxSupprimerPilotes
#
$groupBoxSupprimerPilotes.Controls.Add($BtnSupprimePilote);
$groupBoxSupprimerPilotes.Controls.Add($TxtBoxNomPilote);
$groupBoxSupprimerPilotes.Location = New-Object System.Drawing.Point(12, 172);
$groupBoxSupprimerPilotes.Name = "groupBoxSupprimerPilotes";
$groupBoxSupprimerPilotes.Size = New-Object System.Drawing.Size(623, 69);
$groupBoxSupprimerPilotes.TabIndex = 0;
$groupBoxSupprimerPilotes.TabStop = $false;
$groupBoxSupprimerPilotes.Text = "Supprimer pilotes (nom publié)";
#
# BtnSupprimePilote
#
$BtnSupprimePilote.Location = New-Object System.Drawing.Point(435, 25);
$BtnSupprimePilote.Name = "BtnSupprimePilote";
$BtnSupprimePilote.Size = New-Object System.Drawing.Size(172, 26);
$BtnSupprimePilote.TabIndex = 5;
$BtnSupprimePilote.Text = "Supprimer pilote";
$BtnSupprimePilote.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de suppriemr un ou plusieurs pilotes dans un wim
###########################################################################################################################

function OnClick_BtnSupprimePilote {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnSupprimePilote.Add_Click n'est pas implémenté.");
  
  if ($global:WIMMounted -eq $false){                                         # aucun fichier WIM monté
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{                                        # un WIM est monté et chaine nom de pilote non vide
    if ($TxtBoxNomPilote.Text -eq ""){
                                           # Or Microsoft.VisualBasic.Left(txtDelDriverLocation.Text, 3) <> "inf"
      [void][System.Windows.Forms.MessageBox]::Show("Vous devez entrer un nom de pilote avant de continuer. Le nom du pilote doit se terminer par .inf");
    }
    else{
      write-host 'Dans OnClick_BtnSupprimePilote, valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
      $StrDelDriverLocation = $TxtBoxNomPilote.Text;
      $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Remove-Driver /Driver:" + "`"" + $TxtBoxNomPilote.Text + "`"";
      $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
      $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
      $TxtBoxOutput.Refresh();
      OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
      write-host 'Dans OnClick_BtnSupprimePilote, valeur après exécution de la commande DISM:'$global:StrOutput;
      $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
      $TxtBoxOutput.Refresh();
    }
  }
}

$BtnSupprimePilote.Add_Click( { OnClick_BtnSupprimePilote } );

#
# TxtBoxNomPilote
#
$TxtBoxNomPilote.Location = New-Object System.Drawing.Point(6, 25);
$TxtBoxNomPilote.Name = "TxtBoxNomPilote";
$TxtBoxNomPilote.Size = New-Object System.Drawing.Size(423, 26);
$TxtBoxNomPilote.TabIndex = 0;
#
# groupBoxAjouterPilotes
#
$groupBoxAjouterPilotes.Controls.Add($btnAjouterPilotes);
$groupBoxAjouterPilotes.Controls.Add($LblCheminPilote);
$groupBoxAjouterPilotes.Controls.Add($BtnChoixDossierPilote);
$groupBoxAjouterPilotes.Controls.Add($TxtBoxDossierPilotes);
$groupBoxAjouterPilotes.Controls.Add($ChkBoxRecurse);
$groupBoxAjouterPilotes.Controls.Add($ChkBoxForceUnsigned);
$groupBoxAjouterPilotes.Location = New-Object System.Drawing.Point(12, 6);
$groupBoxAjouterPilotes.Name = "groupBoxAjouterPilotes";
$groupBoxAjouterPilotes.Size = New-Object System.Drawing.Size(623, 160);
$groupBoxAjouterPilotes.TabIndex = 0;
$groupBoxAjouterPilotes.TabStop = $false;
$groupBoxAjouterPilotes.Text = "Ajouter pilotes";
#
# btnAjouterPilotes
#
$btnAjouterPilotes.Location = New-Object System.Drawing.Point(296, 101);
$btnAjouterPilotes.Name = "btnAjouterPilotes";
$btnAjouterPilotes.Size = New-Object System.Drawing.Size(133, 40);
$btnAjouterPilotes.TabIndex = 5;
$btnAjouterPilotes.Text = "Ajouter pilotes";
$btnAjouterPilotes.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'ajouter un ou plusieurs pilotes dans un wim
###########################################################################################################################

function OnClick_btnAjouterPilotes {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement btnAjouterPilotes.Add_Click n'est pas implémenté.");

    if ($global:WIMMounted -eq $false){                          # WIM non monté
      [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM Monté. Vous devez monter un WIM avant d'exécuter cette commande.");
    }
    else{
      write-host 'Dans btnAjouterPilotes, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
      if ($TxtBoxDossierPilotes.Text -eq ""){                    # WIM monté et dossier pilote non référencé
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez spécifier un dossier comportant les pilotes.");
      }
      else{                                                      # WIM monté et dossier pilote renseigné 
        $StrDriverLocation = $TxtBoxDossierPilotes.Text;         # non utile, mémorise dossier pilotes pour un usage futur
        if ($ChkBoxForceUnsigned.Checked -eq $true){            # force l'installation des pilotes non signés
          $global:StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Add-Driver /Driver:" + "`"" + $TxtBoxDossierPilotes.Text + "`"" + " /ForceUnsigned ";
        }
        else{
          $global:StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Add-Driver /Driver:" + "`"" + $TxtBoxDossierPilotes.Text + "`"";
        }
        if ($ChkBoxRecurse.Checked -eq $true){
          $global:StrDISMArguments = $global:StrDISMArguments + " /Recurse";
        }
        $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
        $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
        $TxtBoxOutput.Refresh();
        write-host 'Dans btnAjouterPilotes, valeur actuel de $StrOutput:'$global:StrOutput;

        OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
        write-host 'Dans btnAjouterPilotes, valeur après exécution de la commande DISM:'$global:StrOutput;
        $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
        $TxtBoxOutput.Refresh();
      }
    }
}

$btnAjouterPilotes.Add_Click( { OnClick_btnAjouterPilotes } );

#
# LblCheminPilote
#
$LblCheminPilote.AutoSize = $true;
$LblCheminPilote.Location = New-Object System.Drawing.Point(6, 34);
$LblCheminPilote.Name = "LblCheminPilote";
$LblCheminPilote.Size = New-Object System.Drawing.Size(113, 20);
$LblCheminPilote.TabIndex = 1;
$LblCheminPilote.Text = "Dossier pilotes";
#
# BtnChoixDossierPilote
#
$BtnChoixDossierPilote.Location = New-Object System.Drawing.Point(435, 56);
$BtnChoixDossierPilote.Name = "BtnChoixDossierPilote";
$BtnChoixDossierPilote.Size = New-Object System.Drawing.Size(172, 26);
$BtnChoixDossierPilote.TabIndex = 4;
$BtnChoixDossierPilote.Text = "Choisir dossier pilotes";
$BtnChoixDossierPilote.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir le dossier où se trouve les pilotes
###########################################################################################################################

function OnClick_BtnChoixDossierPilote {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoixDossierPilote.Add_Click n'est pas implémenté.");

    # définit un objet FolderBrowser
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
      RootFolder=[System.Environment+SpecialFolder]'MyComputer'
      SelectedPath = 'C:\'                                     # à partir du dossier c:\
    }
 
    [void]$FolderBrowser.ShowDialog();                         # Affiche l'objet FolderBrowser boite de dialogue
    $TxtBoxDossierPilotes.Text=$FolderBrowser.SelectedPath;    # récupère la sélection de l'utilisateur
}

$BtnChoixDossierPilote.Add_Click( { OnClick_BtnChoixDossierPilote } );

#
# TxtBoxDossierPilotes
#
$TxtBoxDossierPilotes.Location = New-Object System.Drawing.Point(6, 56);
$TxtBoxDossierPilotes.Name = "TxtBoxDossierPilotes";
$TxtBoxDossierPilotes.Size = New-Object System.Drawing.Size(423, 26);
$TxtBoxDossierPilotes.TabIndex = 1;
#
# ChkBoxRecurse
#
$ChkBoxRecurse.AutoSize = $true;
$ChkBoxRecurse.Location = New-Object System.Drawing.Point(171, 100);
$ChkBoxRecurse.Name = "ChkBoxRecurse";
$ChkBoxRecurse.Size = New-Object System.Drawing.Size(88, 24);
$ChkBoxRecurse.TabIndex = 3;
$ChkBoxRecurse.Text = "Recurse";
$ChkBoxRecurse.UseVisualStyleBackColor = $true;
#
# ChkBoxForceUnsigned
#
$ChkBoxForceUnsigned.AutoSize = $true;
$ChkBoxForceUnsigned.Location = New-Object System.Drawing.Point(6, 100);
$ChkBoxForceUnsigned.Name = "ChkBoxForceUnsigned";
$ChkBoxForceUnsigned.Size = New-Object System.Drawing.Size(150, 24);
$ChkBoxForceUnsigned.TabIndex = 2;
$ChkBoxForceUnsigned.Text = "Forced Unsigned";
$ChkBoxForceUnsigned.UseVisualStyleBackColor = $true;
#
# GestionPackage
#
$GestionPackage.Controls.Add($BtnAffichePackagesWim);
$GestionPackage.Controls.Add($groupBox2);
$GestionPackage.Controls.Add($groupBox1);
$GestionPackage.Location = New-Object System.Drawing.Point(4, 29);
$GestionPackage.Name = "GestionPackage";
$GestionPackage.Size = New-Object System.Drawing.Size(882, 257);
$GestionPackage.TabIndex = 2;
$GestionPackage.Text = "Gestion des packages";
$GestionPackage.UseVisualStyleBackColor = $true;
#
# BtnAffichePackagesWim
#
$BtnAffichePackagesWim.Location = New-Object System.Drawing.Point(750, 19);
$BtnAffichePackagesWim.Name = "BtnAffichePackagesWim";
$BtnAffichePackagesWim.Size = New-Object System.Drawing.Size(117, 85);
$BtnAffichePackagesWim.TabIndex = 4;
$BtnAffichePackagesWim.Text = "Affiche les packages du WIM";
$BtnAffichePackagesWim.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les packages présent dans un wim
###########################################################################################################################

function OnClick_BtnAffichePackagesWim {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAffichePackagesWim.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){        # wim non monté
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{                               # wim monté
     write-host 'Dans OnClick_BtnAffichePackagesWim, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:`"$StrMountedImageLocation`" /Get-Packages";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console GUI
     $TxtBoxOutput.Refresh();
     write-host 'Dans OnClick_BtnAffichePackagesWim, valeur actuel de $StrOutput:'$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                # exécution de DISM en mode asynchrone
     write-host 'Dans OnClick_BtnAffichePackagesWim, valeur après exécution de la commande DISM:'$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
     $TxtBoxOutput.Refresh();
  }

}

$BtnAffichePackagesWim.Add_Click( { OnClick_BtnAffichePackagesWim } );

#
# groupBox2
#
$groupBox2.Controls.Add($BtnSupprimePackageBis);
$groupBox2.Controls.Add($BtnSupprimePackage);
$groupBox2.Controls.Add($LblDossierPackagebis);
$groupBox2.Controls.Add($LblNomPackage);
$groupBox2.Controls.Add($TxtBoxDossierPackageBis);
$groupBox2.Controls.Add($TxtBoxNomPackage);
$groupBox2.Location = New-Object System.Drawing.Point(12, 119);
$groupBox2.Name = "groupBox2";
$groupBox2.Size = New-Object System.Drawing.Size(732, 135);
$groupBox2.TabIndex = 1;
$groupBox2.TabStop = $false;
$groupBox2.Text = "Supprimer Packages";
#
# BtnSupprimePackageBis
#
$BtnSupprimePackageBis.Location = New-Object System.Drawing.Point(539, 109);
$BtnSupprimePackageBis.Name = "BtnSupprimePackageBis";
$BtnSupprimePackageBis.Size = New-Object System.Drawing.Size(187, 26);
$BtnSupprimePackageBis.TabIndex = 8;
$BtnSupprimePackageBis.Text = "Supprime Package";
$BtnSupprimePackageBis.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de supprimer un package présent dans un wim
###########################################################################################################################

function OnClick_BtnSupprimePackageBis {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnSupprimePackageBis.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){  # s'assure qu'un fichier WIM est monté
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
    if ($TxtBoxDossierPackageBis.Text -eq ""){
      [void][System.Windows.Forms.MessageBox]::Show("Vous devez saisir un dossier de package avant de continuer, il doit comporter une extension .CAB valide.");
    }
    else{
       write-host 'Dans OnClick_BtnSupprimePackageBis, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
       $StrPackagePath = TxtBoxDossierPackageBis.Text;             # non utile, sauf pour usage ultérieur
       $StrDISMArguments = "/Image:`"$StrMountedImageLocation`" /Remove-Package /PackagePath:"+"`""+$TxtBoxDossierPackageBis.Text+"`"";
       $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
       $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
       $TxtBoxOutput.Refresh();
       write-host 'Dans OnClick_BtnSupprimePackageBis, valeur actuel de $StrOutput:'$global:StrOutput;
       OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
       write-host 'Dans OnClick_BtnSupprimePackageBis, valeur après exécution de la commande DISM:'$global:StrOutput;
       $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
       $TxtBoxOutput.Refresh();
    }
  }
}

$BtnSupprimePackageBis.Add_Click( { OnClick_BtnSupprimePackageBis } );

#
# BtnSupprimePackage
#
$BtnSupprimePackage.Location = New-Object System.Drawing.Point(539, 45);
$BtnSupprimePackage.Name = "BtnSupprimePackage";
$BtnSupprimePackage.Size = New-Object System.Drawing.Size(187, 26);
$BtnSupprimePackage.TabIndex = 7;
$BtnSupprimePackage.Text = "Supprime Package";
$BtnSupprimePackage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de supprimer un package présent dans un wim
###########################################################################################################################

function OnClick_BtnSupprimePackage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnSupprimePackage.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
    if ($TxtBoxNomPackage.Text -eq ""){
       [void][System.Windows.Forms.MessageBox]::Show("Vous devez saisir un nom de package avant de continuer.");
    }
    else{
       write-host 'Dans OnClick_BtnSupprimePackage, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
       $StrPackageName = $TxtBoxNomPackage.Text;    # non utile sauf pour un usage ultérieur
       $StrDISMArguments = "/Image:`"$StrMountedImageLocation`" /Remove-Package /PackageName:"+"`""+$TxtBoxNomPackage.Text+"`"";
       $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
       $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
       $TxtBoxOutput.Refresh();
       write-host 'Dans OnClick_BtnSupprimePackage, valeur actuel de $StrOutput:'$global:StrOutput;
       OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
       write-host 'Dans OnClick_BtnSupprimePackage, valeur après exécution de la commande DISM:'$global:StrOutput;
       $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
       $TxtBoxOutput.Refresh();
    }
  }
}

$BtnSupprimePackage.Add_Click( { OnClick_BtnSupprimePackage } );

#
# LblDossierPackagebis
#
$LblDossierPackagebis.AutoSize = $true;
$LblDossierPackagebis.Location = New-Object System.Drawing.Point(7, 86);
$LblDossierPackagebis.Name = "LblDossierPackagebis";
$LblDossierPackagebis.Size = New-Object System.Drawing.Size(151, 20);
$LblDossierPackagebis.TabIndex = 6;
$LblDossierPackagebis.Text = "Dossier du Package";
#
# LblNomPackage
#
$LblNomPackage.AutoSize = $true;
$LblNomPackage.Location = New-Object System.Drawing.Point(7, 22);
$LblNomPackage.Name = "LblNomPackage";
$LblNomPackage.Size = New-Object System.Drawing.Size(130, 20);
$LblNomPackage.TabIndex = 5;
$LblNomPackage.Text = "Nom du Package";
#
# TxtBoxDossierPackageBis
#
$TxtBoxDossierPackageBis.Location = New-Object System.Drawing.Point(10, 109);
$TxtBoxDossierPackageBis.Name = "TxtBoxDossierPackageBis";
$TxtBoxDossierPackageBis.Size = New-Object System.Drawing.Size(522, 26);
$TxtBoxDossierPackageBis.TabIndex = 4;
#
# TxtBoxNomPackage
#
$TxtBoxNomPackage.Location = New-Object System.Drawing.Point(11, 45);
$TxtBoxNomPackage.Name = "TxtBoxNomPackage";
$TxtBoxNomPackage.Size = New-Object System.Drawing.Size(522, 26);
$TxtBoxNomPackage.TabIndex = 3;
#
# groupBox1
#
$groupBox1.Controls.Add($BtnAjoutPackage);
$groupBox1.Controls.Add($BtnChoisirDossierPackage);
$groupBox1.Controls.Add($ChkBoxIgnoreVerification);
$groupBox1.Controls.Add($LblDossierPackage);
$groupBox1.Controls.Add($TxtBoxDossierPackage);
$groupBox1.Location = New-Object System.Drawing.Point(12, 3);
$groupBox1.Name = "groupBox1";
$groupBox1.Size = New-Object System.Drawing.Size(732, 110);
$groupBox1.TabIndex = 0;
$groupBox1.TabStop = $false;
$groupBox1.Text = "Ajouter Packages";
#
# BtnAjoutPackage
#
$BtnAjoutPackage.Location = New-Object System.Drawing.Point(210, 75);
$BtnAjoutPackage.Name = "BtnAjoutPackage";
$BtnAjoutPackage.Size = New-Object System.Drawing.Size(187, 26);
$BtnAjoutPackage.TabIndex = 6;
$BtnAjoutPackage.Text = "Ajouter Package";
$BtnAjoutPackage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'ajouter un package
###########################################################################################################################

function OnClick_BtnAjoutPackage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAjoutPackage.Add_Click n'est pas implémenté.");

   if ($global:WIMMounted -eq $false){                    # vérifie si une image est montée
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
     if ($TxtBoxDossierPackage.Text -eq  ""){              # chemin vers packages présent ?
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez spécifier un dossier ou se trouve le package.");
     }
     else{
        write-host 'Dans OnClick_BtnAjoutPackage, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
        $StrPackageLocation = $TxtBoxDossierPackage.Text;  # non utile, sauf pour un usage ultérieur
        if ($ChkBoxIgnoreVerification.Checked -eq $true){  # ignore les vérifications
           $BlnIgnoreCheck = $true;           
           $StrDISMArguments = "/Image:`"$StrMountedImageLocation`" /Add-Package /PackagePath:"+"`""+$TxtBoxDossierPackage.Text+"`""+" /IgnoreCheck";
        }
        else{
           $BlnIgnoreCheck = $false;                      # effectue les vérifications
           $StrDISMArguments = "/Image:`"$StrMountedImageLocation`" /Add-Package /PackagePath:"+"`""+$TxtBoxDossierPackage.Text+"`"";
        }
        $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
        $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
        $TxtBoxOutput.Refresh();
        write-host 'Dans OnClick_BtnAjoutPackage, valeur actuel de $StrOutput:'$global:StrOutput;
        OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
        $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
        $TxtBoxOutput.Refresh();
     }
  }
}

$BtnAjoutPackage.Add_Click( { OnClick_BtnAjoutPackage } );

#
# BtnChoisirDossierPackage
#
$BtnChoisirDossierPackage.Location = New-Object System.Drawing.Point(539, 45);
$BtnChoisirDossierPackage.Name = "BtnChoisirDossierPackage";
$BtnChoisirDossierPackage.Size = New-Object System.Drawing.Size(187, 26);
$BtnChoisirDossierPackage.TabIndex = 5;
$BtnChoisirDossierPackage.Text = "Choisir dossier package";
$BtnChoisirDossierPackage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir un package
###########################################################################################################################

function OnClick_BtnChoisirDossierPackage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoisirDossierPackage.Add_Click n'est pas implémenté.");

   # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                    # à partir du dossier c:\
   }
 
   [void]$FolderBrowser.ShowDialog();                        # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxDossierPackage.Text=$FolderBrowser.SelectedPath;   # récupère la sélection de l'utilisateur
}

$BtnChoisirDossierPackage.Add_Click( { OnClick_BtnChoisirDossierPackage } );

#
# ChkBoxIgnoreVerification
#
$ChkBoxIgnoreVerification.AutoSize = $true;
$ChkBoxIgnoreVerification.Location = New-Object System.Drawing.Point(6, 77);
$ChkBoxIgnoreVerification.Name = "ChkBoxIgnoreVerification";
$ChkBoxIgnoreVerification.Size = New-Object System.Drawing.Size(157, 24);
$ChkBoxIgnoreVerification.TabIndex = 2;
$ChkBoxIgnoreVerification.Text = "Ignore Vérification";
$ChkBoxIgnoreVerification.UseVisualStyleBackColor = $true;
#
# LblDossierPackage
#
$LblDossierPackage.AutoSize = $true;
$LblDossierPackage.Location = New-Object System.Drawing.Point(6, 22);
$LblDossierPackage.Name = "LblDossierPackage";
$LblDossierPackage.Size = New-Object System.Drawing.Size(129, 20);
$LblDossierPackage.TabIndex = 3;
$LblDossierPackage.Text = "Dossier Package";
#
# TxtBoxDossierPackage
#
$TxtBoxDossierPackage.Location = New-Object System.Drawing.Point(6, 45);
$TxtBoxDossierPackage.Name = "TxtBoxDossierPackage";
$TxtBoxDossierPackage.Size = New-Object System.Drawing.Size(527, 26);
$TxtBoxDossierPackage.TabIndex = 2;
#
# GestionFeature
#
$GestionFeature.Controls.Add($label4);
$GestionFeature.Controls.Add($label3);
$GestionFeature.Controls.Add($label2);
$GestionFeature.Controls.Add($BtnDisableFeature);
$GestionFeature.Controls.Add($BtnEnableFeature);
$GestionFeature.Controls.Add($BtnAfficheFeatureWim);
$GestionFeature.Controls.Add($ChkBoxEnablePackagePath);
$GestionFeature.Controls.Add($ChkBoxEnablePackageName);
$GestionFeature.Controls.Add($TxtBoxFolderPackage);
$GestionFeature.Controls.Add($TxtBoxFeaturePackageName);
$GestionFeature.Controls.Add($TxtBoxFeatureName);
$GestionFeature.Location = New-Object System.Drawing.Point(4, 29);
$GestionFeature.Name = "GestionFeature";
$GestionFeature.Size = New-Object System.Drawing.Size(882, 257);
$GestionFeature.TabIndex = 3;
$GestionFeature.Text = "Gestion des features";
$GestionFeature.UseVisualStyleBackColor = $true;
#
# label4
#
$label4.AutoSize = $true;
$label4.Location = New-Object System.Drawing.Point(29, 149);
$label4.Name = "label4";
$label4.Size = New-Object System.Drawing.Size(150, 20);
$label4.TabIndex = 10;
$label4.Text = "Dossier du package";
#
# label3
#
$label3.AutoSize = $true;
$label3.Location = New-Object System.Drawing.Point(29, 83);
$label3.Name = "label3";
$label3.Size = New-Object System.Drawing.Size(129, 20);
$label3.TabIndex = 9;
$label3.Text = "Nom du package";
#
# label2
#
$label2.AutoSize = $true;
$label2.Location = New-Object System.Drawing.Point(29, 16);
$label2.Name = "label2";
$label2.Size = New-Object System.Drawing.Size(124, 20);
$label2.TabIndex = 8;
$label2.Text = "Nom du Feature";
#
# BtnDisableFeature
#
$BtnDisableFeature.Location = New-Object System.Drawing.Point(451, 163);
$BtnDisableFeature.Name = "BtnDisableFeature";
$BtnDisableFeature.Size = New-Object System.Drawing.Size(240, 65);
$BtnDisableFeature.TabIndex = 7;
$BtnDisableFeature.Text = "Désactive un Feature";
$BtnDisableFeature.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de desactiver un feature présent dans un wim
###########################################################################################################################

function OnClick_BtnDisableFeature {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDisableFeature.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     if ($TxtBoxFeatureName.Text -eq ""){
       [void][System.Windows.Forms.MessageBox]::Show("Un nom de feature est requis pour continuer.");
     }
     else{
        if (($ChkBoxEnablePackageName.Checked -eq $true) -and ($TxtBoxFeaturePackageName.Text -eq "")){
          [void][System.Windows.Forms.MessageBox]::Show("si vous activez le champs nom du package, vous devez spécifier le nom du package");
        }
        else{
           if ($ChkBoxEnablePackagePath.Checked -eq $true){
             [void][System.Windows.Forms.MessageBox]::Show("L'option dossier package ne peut être utilisé pour désactiver un feature. La valeur de ce champ sera ignoré.");
           }
           else{
              write-host 'Dans OnClick_BtnDisableFeature, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
              $StrFeatureName = $TxtBoxFeatureName.Text;
              $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Disable-Feature /FeatureName:" + "`"" + $TxtBoxFeatureName.Text + "`"";
              if ($ChkBoxEnablePackageName.Checked -eq $true){
                $StrDISMArguments = $StrDISMArguments + "/PackageName:" + "`"" + $TxtBoxFeaturePackageName.Text + "`"";
              }
              $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
              $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
              $TxtBoxOutput.Refresh();
              write-host 'Dans OnClick_BtnDisableFeature, valeur actuel de $StrOutput:'$global:StrOutput;
              OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
              $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
              $TxtBoxOutput.Refresh();
           }
       }
    }
  }
}

$BtnDisableFeature.Add_Click( { OnClick_BtnDisableFeature } );

#
# BtnEnableFeature
#
$BtnEnableFeature.Location = New-Object System.Drawing.Point(451, 87);
$BtnEnableFeature.Name = "BtnEnableFeature";
$BtnEnableFeature.Size = New-Object System.Drawing.Size(240, 70);
$BtnEnableFeature.TabIndex = 6;
$BtnEnableFeature.Text = "Active un Feature";
$BtnEnableFeature.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'activer un feature présent dans un wim
###########################################################################################################################

function OnClick_BtnEnableFeature {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnEnableFeature.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     if ($TxtBoxFeatureName.Text -eq ""){
       [void][System.Windows.Forms.MessageBox]::Show("La saisie du champ nom feature est requise pour continuer.");
     }
     else{
        if (($ChkBoxEnablePackageName.Checked -eq $true) -and ($TxtBoxFeaturePackageName.Text -eq "")){
          [void][System.Windows.Forms.MessageBox]::Show("Si vous validez le champ nom package, vous devez le renseigner");
        }
        else{
           if (($ChkBoxEnablePackagePath.Checked -eq $true) -and ($TxtBoxFolderPackage.Text -eq "")){
             [void][System.Windows.Forms.MessageBox]::Show("Si vous validez le champ dossier package, vous devez le renseigner");
           }
           else{
              $StrFeatureName = $TxtBoxFeatureName.Text;  # non utile, sauf pour un usage futur
              $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Enable-Feature /FeatureName:" + "`"" + $TxtBoxFeatureName.Text + "`"";
              if ($ChkBoxEnablePackageName.Checked -eq $true){
                $StrDISMArguments = $StrDISMArguments + "/PackageName:" + "`"" + $TxtBoxFeaturePackageName.Text + "`"";
              }
              else{
                 if ($ChkBoxEnablePackagePath.Checked -eq $true){
                   $StrDISMArguments = $StrDISMArguments + "/PackagePath:" + "`"" + $TxtBoxFolderPackage.Text + "`"";
                 }
                 write-host 'Dans OnClick_BtnEnableFeature, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
                 $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
                 $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
                 $TxtBoxOutput.Refresh();
                 write-host 'Dans OnClick_BtnEnableFeature, valeur actuel de $StrOutput:'$global:StrOutput;
                 OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
                 $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
                 $TxtBoxOutput.Refresh();
              }
           }
        }
     }
  }
}

$BtnEnableFeature.Add_Click( { OnClick_BtnEnableFeature } );

#
# BtnAfficheFeatureWim
#
$BtnAfficheFeatureWim.Location = New-Object System.Drawing.Point(451, 16);
$BtnAfficheFeatureWim.Name = "BtnAfficheFeatureWim";
$BtnAfficheFeatureWim.Size = New-Object System.Drawing.Size(240, 65);
$BtnAfficheFeatureWim.TabIndex = 5;
$BtnAfficheFeatureWim.Text = "Affiche les Features présent dans le WIM";
$BtnAfficheFeatureWim.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les features présent dans un wim
###########################################################################################################################

function OnClick_BtnAfficheFeatureWim {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheFeatureWim.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
  [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     write-host 'Dans OnClick_BtnAfficheFeatureWim, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-Features";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     write-host "OnClick_BtnAfficheFeatureWim (avant), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console GUI
     $TxtBoxOutput.Refresh();
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;                 # exécution de DISM en mode asynchrone
     $TxtBoxOutput.Text=$global:StrOutput;                                   # Affiche le résultat dans la console
     write-host "OnClick_BtnAfficheFeatureWim (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Refresh();
  }
}

$BtnAfficheFeatureWim.Add_Click( { OnClick_BtnAfficheFeatureWim } );

#
# ChkBoxEnablePackagePath
#
$ChkBoxEnablePackagePath.AutoSize = $true;
$ChkBoxEnablePackagePath.Location = New-Object System.Drawing.Point(12, 179);
$ChkBoxEnablePackagePath.Name = "ChkBoxEnablePackagePath";
$ChkBoxEnablePackagePath.Size = New-Object System.Drawing.Size(15, 14);
$ChkBoxEnablePackagePath.TabIndex = 4;
$ChkBoxEnablePackagePath.UseVisualStyleBackColor = $true;
#
# ChkBoxEnablePackageName
#
$ChkBoxEnablePackageName.AutoSize = $true;
$ChkBoxEnablePackageName.Location = New-Object System.Drawing.Point(12, 109);
$ChkBoxEnablePackageName.Name = "ChkBoxEnablePackageName";
$ChkBoxEnablePackageName.Size = New-Object System.Drawing.Size(15, 14);
$ChkBoxEnablePackageName.TabIndex = 3;
$ChkBoxEnablePackageName.UseVisualStyleBackColor = $true;
#
# TxtBoxFolderPackage
#
$TxtBoxFolderPackage.Location = New-Object System.Drawing.Point(33, 172);
$TxtBoxFolderPackage.Name = "TxtBoxFolderPackage";
$TxtBoxFolderPackage.Size = New-Object System.Drawing.Size(385, 26);
$TxtBoxFolderPackage.TabIndex = 2;
#
# TxtBoxFeaturePackageName
#
$TxtBoxFeaturePackageName.Location = New-Object System.Drawing.Point(33, 106);
$TxtBoxFeaturePackageName.Name = "TxtBoxFeaturePackageName";
$TxtBoxFeaturePackageName.Size = New-Object System.Drawing.Size(385, 26);
$TxtBoxFeaturePackageName.TabIndex = 1;
#
# TxtBoxFeatureName
#
$TxtBoxFeatureName.Location = New-Object System.Drawing.Point(33, 39);
$TxtBoxFeatureName.Name = "TxtBoxFeatureName";
$TxtBoxFeatureName.Size = New-Object System.Drawing.Size(385, 26);
$TxtBoxFeatureName.TabIndex = 0;
#
# ServiceEdition
#
$ServiceEdition.Controls.Add($LblEdition);
$ServiceEdition.Controls.Add($LblProductKey);
$ServiceEdition.Controls.Add($BtnFixeEdition);
$ServiceEdition.Controls.Add($BtnFixeCleProduit);
$ServiceEdition.Controls.Add($BtnAfficheEditionCible);
$ServiceEdition.Controls.Add($BtnAfficheEditionCourante);
$ServiceEdition.Controls.Add($TxtBoxEdition);
$ServiceEdition.Controls.Add($TxtBoxProductKey);
$ServiceEdition.Location = New-Object System.Drawing.Point(4, 29);
$ServiceEdition.Name = "ServiceEdition";
$ServiceEdition.Size = New-Object System.Drawing.Size(882, 257);
$ServiceEdition.TabIndex = 4;
$ServiceEdition.Text = "Service Edition";
$ServiceEdition.UseVisualStyleBackColor = $true;
#
# LblEdition
#
$LblEdition.AutoSize = $true;
$LblEdition.Location = New-Object System.Drawing.Point(27, 118);
$LblEdition.Name = "LblEdition";
$LblEdition.Size = New-Object System.Drawing.Size(58, 20);
$LblEdition.TabIndex = 7;
$LblEdition.Text = "Edition";
#
# LblProductKey
#
$LblProductKey.AutoSize = $true;
$LblProductKey.Location = New-Object System.Drawing.Point(27, 13);
$LblProductKey.Name = "LblProductKey";
$LblProductKey.Size = New-Object System.Drawing.Size(86, 20);
$LblProductKey.TabIndex = 6;
$LblProductKey.Text = "Clé Produit";
#
# BtnFixeEdition
#
$BtnFixeEdition.Location = New-Object System.Drawing.Point(31, 173);
$BtnFixeEdition.Name = "BtnFixeEdition";
$BtnFixeEdition.Size = New-Object System.Drawing.Size(138, 39);
$BtnFixeEdition.TabIndex = 5;
$BtnFixeEdition.Text = "Fixe édition";
$BtnFixeEdition.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de fixer l'édition cible
###########################################################################################################################

function OnClick_BtnFixeEdition {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnFixeEdition.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     write-host 'Dans OnClick_BtnFixeEdition, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:" + $StrMountedImageLocation + " /Get-TargetEditions";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
     write-host "OnClick_BtnFixeEdition (avant), contenu de la variable: "$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host "OnClick_BtnFixeEdition (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
  }
}

$BtnFixeEdition.Add_Click( { OnClick_BtnFixeEdition } );

#
# BtnFixeCleProduit
#
$BtnFixeCleProduit.Location = New-Object System.Drawing.Point(31, 68);
$BtnFixeCleProduit.Name = "BtnFixeCleProduit";
$BtnFixeCleProduit.Size = New-Object System.Drawing.Size(138, 34);
$BtnFixeCleProduit.TabIndex = 4;
$BtnFixeCleProduit.Text = "Fixe clé produit";
$BtnFixeCleProduit.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de fixer la clé produit
###########################################################################################################################

function OnClick_BtnFixeCleProduit {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnFixeCleProduit.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     if ($TxtBoxProductKey.Text -eq ""){
        [void][System.Windows.Forms.MessageBox]::Show("Une clé produit est requise pour continuer.");
     }
     else{
       write-host 'Dans OnClick_BtnFixeCleProduit, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
       $StrProductKey = $TxtBoxProductKey.Text;
       $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Set-ProductKey:" + $StrProductKey;
       $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
       $TxtBoxOutput.Text = $global:StrOutput;
       $TxtBoxOutput.Refresh();
       write-host "OnClick_BtnFixeCleProduit (avant), contenu de la variable: "$global:StrOutput;
       OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
       write-host "OnClick_BtnFixeCleProduit (après), contenu de la variable: "$global:StrOutput;
       $TxtBoxOutput.Text = $global:StrOutput;
       $TxtBoxOutput.Refresh();
     }
  }
}

$BtnFixeCleProduit.Add_Click( { OnClick_BtnFixeCleProduit } );

#
# BtnAfficheEditionCible
#
$BtnAfficheEditionCible.Location = New-Object System.Drawing.Point(529, 130);
$BtnAfficheEditionCible.Name = "BtnAfficheEditionCible";
$BtnAfficheEditionCible.Size = New-Object System.Drawing.Size(156, 49);
$BtnAfficheEditionCible.TabIndex = 3;
$BtnAfficheEditionCible.Text = "Affiche Les éditions cible";
$BtnAfficheEditionCible.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher l'édition cible
###########################################################################################################################

function OnClick_BtnAfficheEditionCible {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheEditionCible.Add_Click n'est pas implémenté.");

   if ($WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
     write-host 'Dans OnClick_BtnAfficheEditionCible, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:" + $global:StrMountedImageLocation + " /Get-TargetEditions";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
     write-host "OnClick_BtnAfficheEditionCible (avant), contenu de la variable: "$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host "OnClick_BtnAfficheEditionCible (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
   }
}

$BtnAfficheEditionCible.Add_Click( { OnClick_BtnAfficheEditionCible } );

#
# BtnAfficheEditionCourante
#
$BtnAfficheEditionCourante.Location = New-Object System.Drawing.Point(529, 21);
$BtnAfficheEditionCourante.Name = "BtnAfficheEditionCourante";
$BtnAfficheEditionCourante.Size = New-Object System.Drawing.Size(156, 56);
$BtnAfficheEditionCourante.TabIndex = 2;
$BtnAfficheEditionCourante.Text = "Affiche édition courante";
$BtnAfficheEditionCourante.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher l'édition courante Menu Service Edition
###########################################################################################################################

function OnClick_BtnAfficheEditionCourante {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheEditionCourante.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     write-host 'Dans OnClick_BtnAfficheEditionCourante, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     $StrDISMArguments = "/Image:" + $global:StrMountedImageLocation + " /Get-CurrentEdition";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
     write-host "OnClick_BtnAfficheEditionCourante (avant), contenu de la variable: "$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host "OnClick_BtnAfficheEditionCourante (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
  }
}

$BtnAfficheEditionCourante.Add_Click( { OnClick_BtnAfficheEditionCourante } );

#
# TxtBoxEdition
#
$TxtBoxEdition.Location = New-Object System.Drawing.Point(31, 141);
$TxtBoxEdition.Name = "TxtBoxEdition";
$TxtBoxEdition.Size = New-Object System.Drawing.Size(492, 26);
$TxtBoxEdition.TabIndex = 1;
#
# TxtBoxProductKey
#
$TxtBoxProductKey.Location = New-Object System.Drawing.Point(31, 36);
$TxtBoxProductKey.Name = "TxtBoxProductKey";
$TxtBoxProductKey.Size = New-Object System.Drawing.Size(492, 26);
$TxtBoxProductKey.TabIndex = 0;
#
# ServiceUnattend
#
$ServiceUnattend.Controls.Add($BtnAppliqueUnattendXML);
$ServiceUnattend.Controls.Add($BtnChoisirXMLUnattend);
$ServiceUnattend.Controls.Add($TxtBoxFichierXMLUnattend);
$ServiceUnattend.Controls.Add($LblFichierXMLUnattend);
$ServiceUnattend.Location = New-Object System.Drawing.Point(4, 29);
$ServiceUnattend.Name = "ServiceUnattend";
$ServiceUnattend.Size = New-Object System.Drawing.Size(882, 257);
$ServiceUnattend.TabIndex = 5;
$ServiceUnattend.Text = "Service Unattend";
$ServiceUnattend.UseVisualStyleBackColor = $true;
#
# BtnAppliqueUnattendXML
#
$BtnAppliqueUnattendXML.Location = New-Object System.Drawing.Point(561, 13);
$BtnAppliqueUnattendXML.Name = "BtnAppliqueUnattendXML";
$BtnAppliqueUnattendXML.Size = New-Object System.Drawing.Size(145, 88);
$BtnAppliqueUnattendXML.TabIndex = 3;
$BtnAppliqueUnattendXML.Text = "Applique Unattend.xml";
$BtnAppliqueUnattendXML.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'appliquer un fichier Unattend.XML
###########################################################################################################################

function OnClick_BtnAppliqueUnattendXML {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAppliqueUnattendXML.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq  $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     if ($TxtBoxFichierXMLUnattend.Text -eq ""){
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez spécifier un fichier XML.");
     }
     else{
        write-host 'Dans OnClick_BtnAppliqueUnattendXML, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
        $StrXMLFileName = $TxtBoxFichierXMLUnattend.Text;
        $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Apply-Unattend:" + "`"" + $TxtBoxFichierXMLUnattend.Text + "`"";
        $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
        write-host "OnClick_BtnAppliqueUnattendXML (avant), contenu de la variable: "$global:StrOutput;
        OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
        write-host "OnClick_BtnAppliqueUnattendXML (après), contenu de la variable: "$global:StrOutput;
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
     }
  }
}

$BtnAppliqueUnattendXML.Add_Click( { OnClick_BtnAppliqueUnattendXML } );

#
# BtnChoisirXMLUnattend
#
$BtnChoisirXMLUnattend.Location = New-Object System.Drawing.Point(393, 44);
$BtnChoisirXMLUnattend.Name = "BtnChoisirXMLUnattend";
$BtnChoisirXMLUnattend.Size = New-Object System.Drawing.Size(162, 26);
$BtnChoisirXMLUnattend.TabIndex = 2;
$BtnChoisirXMLUnattend.Text = "Choisir fichier XML";
$BtnChoisirXMLUnattend.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir un fichier Unattend.xml
###########################################################################################################################

function OnClick_BtnChoisirXMLUnattend {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoisirXMLUnattend.Add_Click n'est pas implémenté.");

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    Title = "Choisir un fichier XML ouvrir"
    Filter = 'Fichier XML (*.xml)|*.xml|All Files (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxFichierXMLUnattend.Text = $FileBrowser.FileName;
  }
}

$BtnChoisirXMLUnattend.Add_Click( { OnClick_BtnChoisirXMLUnattend } );

#
# TxtBoxFichierXMLUnattend
#
$TxtBoxFichierXMLUnattend.Location = New-Object System.Drawing.Point(12, 44);
$TxtBoxFichierXMLUnattend.Name = "TxtBoxFichierXMLUnattend";
$TxtBoxFichierXMLUnattend.Size = New-Object System.Drawing.Size(375, 26);
$TxtBoxFichierXMLUnattend.TabIndex = 1;
#
# LblFichierXMLUnattend
#
$LblFichierXMLUnattend.AutoSize = $true;
$LblFichierXMLUnattend.Location = New-Object System.Drawing.Point(8, 21);
$LblFichierXMLUnattend.Name = "LblFichierXMLUnattend";
$LblFichierXMLUnattend.Size = New-Object System.Drawing.Size(164, 20);
$LblFichierXMLUnattend.TabIndex = 0;
$LblFichierXMLUnattend.Text = "Fichier XML Unattend";
#
# ServiceApplication
#
$ServiceApplication.Controls.Add($BtnVerifierPatchsApplication);
$ServiceApplication.Controls.Add($LblFichierMSP);
$ServiceApplication.Controls.Add($LblPatchCode);
$ServiceApplication.Controls.Add($LblCodeProduit);
$ServiceApplication.Controls.Add($BtnChoisirFichierMSP);
$ServiceApplication.Controls.Add($BtnAfficheInfosPatchsApplications);
$ServiceApplication.Controls.Add($BtnAfficheApplicationsPatch);
$ServiceApplication.Controls.Add($BtnAfficheInfosApplications);
$ServiceApplication.Controls.Add($btnAfficheApplication);
$ServiceApplication.Controls.Add($TxtBoxNomFichierMSP);
$ServiceApplication.Controls.Add($TxtBoxPatchCode);
$ServiceApplication.Controls.Add($TxtBoxCodeProduit)
$ServiceApplication.Location = New-Object System.Drawing.Point(4, 29);
$ServiceApplication.Name = "ServiceApplication";
$ServiceApplication.Size = New-Object System.Drawing.Size(882, 257);
$ServiceApplication.TabIndex = 6;
$ServiceApplication.Text = "Service Application";
$ServiceApplication.UseVisualStyleBackColor = $true;
#
# BtnVerifierPatchsApplication
#
$BtnVerifierPatchsApplication.Location = New-Object System.Drawing.Point(38, 197);
$BtnVerifierPatchsApplication.Name = "BtnVerifierPatchsApplication";
$BtnVerifierPatchsApplication.Size = New-Object System.Drawing.Size(292, 40);
$BtnVerifierPatchsApplication.TabIndex = 11;
$BtnVerifierPatchsApplication.Text = "Vérifier les Patchs d'application";
$BtnVerifierPatchsApplication.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de vérifier les patch application
###########################################################################################################################

function OnClick_BtnVerifierPatchsApplication {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnVerifierPatchsApplication.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
    [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     write-host 'Dans OnClick_BtnVerifierPatchsApplication, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
     if ($TxtBoxNomFichierMSP.Text -eq ""){
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez entrer un fichier MSP.");
     }
     else{
        $StrMSPFileName = $TxtBoxNomFichierMSP.Text;
        $StrDISMArguments = "/Image:" + $global:StrMountedImageLocation + " /Check-AppPatch /PatchLocation:" + $StrMSPFileName;
        $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
        write-host "OnClick_BtnVerifierPatchsApplication (avant), contenu de la variable: "$global:StrOutput;
        OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
        write-host "OnClick_BtnVerifierPatchsApplication (après), contenu de la variable: "$global:StrOutput;
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
     }
  }
}

$BtnVerifierPatchsApplication.Add_Click( { OnClick_BtnVerifierPatchsApplication } );

#
# LblFichierMSP
#
$LblFichierMSP.AutoSize = $true;
$LblFichierMSP.Location = New-Object System.Drawing.Point(4, 130);
$LblFichierMSP.Name = "LblFichierMSP";
$LblFichierMSP.Size = New-Object System.Drawing.Size(94, 20);
$LblFichierMSP.TabIndex = 10;
$LblFichierMSP.Text = "Fichier MSP";
#
# LblPatchCode
#
$LblPatchCode.AutoSize = $true;
$LblPatchCode.Location = New-Object System.Drawing.Point(4, 69);
$LblPatchCode.Name = "LblPatchCode";
$LblPatchCode.Size = New-Object System.Drawing.Size(89, 20);
$LblPatchCode.TabIndex = 9;
$LblPatchCode.Text = "Patch code";
#
# LblCodeProduit
#
$LblCodeProduit.AutoSize = $true;
$LblCodeProduit.Location = New-Object System.Drawing.Point(4, 8);
$LblCodeProduit.Name = "LblCodeProduit";
$LblCodeProduit.Size = New-Object System.Drawing.Size(100, 20);
$LblCodeProduit.TabIndex = 8;
$LblCodeProduit.Text = "Code produit";
#
# BtnChoisirFichierMSP
#
$BtnChoisirFichierMSP.Location = New-Object System.Drawing.Point(379, 153);
$BtnChoisirFichierMSP.Name = "BtnChoisirFichierMSP";
$BtnChoisirFichierMSP.Size = New-Object System.Drawing.Size(159, 26);
$BtnChoisirFichierMSP.TabIndex = 7;
$BtnChoisirFichierMSP.Text = "Choisir fichier MSP";
$BtnChoisirFichierMSP.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir un fichier MSP (patch microsoft)
###########################################################################################################################

function OnClick_BtnChoisirFichierMSP {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnChoisirFichierMSP.Add_Click n'est pas implémenté.");

  [String]$StrMSPFileName;

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    Title = "Choisir un fichier MSP à ouvrir"
    Filter = 'Fichier MSP (*.msp)|*.msp|Tous Fichiers (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $StrMSPFileName = $FileBrowser.FileName;
    $TxtBoxNomFichierMSP.Text = $StrMSPFileName;
  }
}

$BtnChoisirFichierMSP.Add_Click( { OnClick_BtnChoisirFichierMSP } );

#
# BtnAfficheInfosPatchsApplications
#
$BtnAfficheInfosPatchsApplications.Location = New-Object System.Drawing.Point(559, 184);
$BtnAfficheInfosPatchsApplications.Name = "BtnAfficheInfosPatchsApplications";
$BtnAfficheInfosPatchsApplications.Size = New-Object System.Drawing.Size(257, 53);
$BtnAfficheInfosPatchsApplications.TabIndex = 6;
$BtnAfficheInfosPatchsApplications.Text = "Affiche les infos des patchs d'applications";
$BtnAfficheInfosPatchsApplications.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les informations sur les patchs d'applications
###########################################################################################################################

function OnClick_BtnAfficheInfosPatchsApplications {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheInfosPatchsApplications.Add_Click n'est pas implémenté.");

   if ($WIMMounted -eq $false){
      [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
      if (($TxtBoxPatchCode.Text -eq "{        -    -    -    -            }") -and ($TxtBoxCodeProduit.Text -eq "{        -    -    -    -            }")){
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppPatchInfo";
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosPatchsApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosPatchsApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
      if (($TxtBoxPatchCode.Text -ne "{        -    -    -    -            }") -and ($TxtBoxCodeProduit.Text -eq "{        -    -    -    -            }")){
         $StrPatchCode = $TxtBoxPatchCode.Text;
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" +$global:StrMountedImageLocation + "`"" + " /Get-AppPatchInfo /PatchCode:" + $StrPatchCode;
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosPatchsApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosPatchsApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
      if (($TxtBoxPatchCode.Text -eq "{        -    -    -    -            }") -and ($TxtBoxCodeProduit.Text -ne "{        -    -    -    -            }")){
         $StrPatchCode = $TxtBoxPatchCode.Text;
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppPatchInfo /ProductCode:" + $StrProductCode;
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosPatchsApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosPatchsApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
      if (($TxtBoxPatchCode.Text -ne "{        -    -    -    -            }") -and ($TxtBoxCodeProduit.Text -ne "{        -    -    -    -            }")){
         $StrPatchCode = $TxtBoxPatchCode.Text;
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppPatchInfo /PatchCode:" + $StrPatchCode + " /ProductCode:" + $StrProductCode;
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosPatchsApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosPatchsApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
   }
}

$BtnAfficheInfosPatchsApplications.Add_Click( { OnClick_BtnAfficheInfosPatchsApplications } );

#
# BtnAfficheApplicationsPatch
#
$BtnAfficheApplicationsPatch.Location = New-Object System.Drawing.Point(559, 127);
$BtnAfficheApplicationsPatch.Name = "BtnAfficheApplicationsPatch";
$BtnAfficheApplicationsPatch.Size = New-Object System.Drawing.Size(257, 42);
$BtnAfficheApplicationsPatch.TabIndex = 5;
$BtnAfficheApplicationsPatch.Text = "Affiche les patchs d'applications";
$BtnAfficheApplicationsPatch.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les patches d'applications
###########################################################################################################################

function OnClick_BtnAfficheApplicationsPatch {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheApplicationsPatch.Add_Click n'est pas implémenté.");

   if ($WIMMounted -eq $false){
      [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
      write-host 'Dans OnClick_BtnAfficheApplicationsPatch, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
      if ($TxtBoxCodeProduit.Text -eq "{        -    -    -    -            }"){
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppPatches";
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheApplicationsPatch (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheApplicationsPatch (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh() ;
      }
      else{
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppPatches  /ProductCode:" + $StrProductCode;
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheApplicationsPatch (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheApplicationsPatch (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
   }
}

$BtnAfficheApplicationsPatch.Add_Click( { OnClick_BtnAfficheApplicationsPatch } );

#
# BtnAfficheInfosApplications
#
$BtnAfficheInfosApplications.Location = New-Object System.Drawing.Point(559, 68);
$BtnAfficheInfosApplications.Name = "BtnAfficheInfosApplications";
$BtnAfficheInfosApplications.Size = New-Object System.Drawing.Size(257, 45);
$BtnAfficheInfosApplications.TabIndex = 4;
$BtnAfficheInfosApplications.Text = "Affiche les infos des applications";
$BtnAfficheInfosApplications.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les infos des applications
###########################################################################################################################

function OnClick_BtnAfficheInfosApplications {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAfficheInfosApplications.Add_Click n'est pas implémenté.");

   if ($WIMMounted -eq $false){
      [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
      write-host 'Dans OnClick_BtnAfficheInfosApplications, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
      if ($TxtBoxCodeProduit.Text -eq "{        -    -    -    -            }"){
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Get-AppInfo";
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
      else{
         $StrProductCode = $TxtBoxCodeProduit.Text;
         $StrDISMArguments = "/Image:" + "`"" + $global:StrMountedImageLocation + "`"" + " /Get-AppInfo /ProductCode:" + $StrProductCode;
         $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
         write-host "OnClick_BtnAfficheInfosApplications (avant), contenu de la variable: "$global:StrOutput;
         OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
         write-host "OnClick_BtnAfficheInfosApplications (après), contenu de la variable: "$global:StrOutput;
         $TxtBoxOutput.Text = $global:StrOutput;
         $TxtBoxOutput.Refresh();
      }
   }
}

$BtnAfficheInfosApplications.Add_Click( { OnClick_BtnAfficheInfosApplications } );

#
# btnAfficheApplication
#
$btnAfficheApplication.Location = New-Object System.Drawing.Point(559, 14);
$btnAfficheApplication.Name = "btnAfficheApplication";
$btnAfficheApplication.Size = New-Object System.Drawing.Size(257, 43);
$btnAfficheApplication.TabIndex = 3;
$btnAfficheApplication.Text = "Affiche les applications";
$btnAfficheApplication.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les applications
###########################################################################################################################

function OnClick_btnAfficheApplication {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement btnAfficheApplication.Add_Click n'est pas implémenté.");

   if ($WIMMounted -eq $false){
      [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
   }
   else{
      write-host 'Dans OnClick_btnAfficheApplication, Valeur de la variable $global:StrMountedImageLocation:'$global:StrMountedImageLocation;
      $StrDISMArguments = "/Image:" + $global:StrMountedImageLocation + " /Get-Apps";
      $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
      $TxtBoxOutput.Text = $global:StrOutput;
      $TxtBoxOutput.Refresh();
      write-host "OnClick_btnAfficheApplication (avant), contenu de la variable: "$global:StrOutput;
      OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
      write-host "OnClick_btnAfficheApplication (après), contenu de la variable: "$global:StrOutput;
      $TxtBoxOutput.Text = $global:StrOutput;
      $TxtBoxOutput.Refresh();
   }
}

$btnAfficheApplication.Add_Click( { OnClick_btnAfficheApplication } );

#
# TxtBoxNomFichierMSP
#
$TxtBoxNomFichierMSP.Location = New-Object System.Drawing.Point(8, 153);
$TxtBoxNomFichierMSP.Name = "TxtBoxNomFichierMSP";
$TxtBoxNomFichierMSP.Size = New-Object System.Drawing.Size(365, 26);
$TxtBoxNomFichierMSP.TabIndex = 2;
#
# TxtBoxPatchCode
#
$TxtBoxPatchCode.Location = New-Object System.Drawing.Point(8, 92);
$TxtBoxPatchCode.Name = "TxtBoxPatchCode";
$TxtBoxPatchCode.Size = New-Object System.Drawing.Size(365, 26);
$TxtBoxPatchCode.TabIndex = 1;
#
# TxtBoxCodeProduit
#
$TxtBoxCodeProduit.Location = New-Object System.Drawing.Point(8, 31);
$TxtBoxCodeProduit.Name = "TxtBoxCodeProduit";
$TxtBoxCodeProduit.Size = New-Object System.Drawing.Size(365, 26);
$TxtBoxCodeProduit.TabIndex = 0;
#
# CaptureImage
#
$CaptureImage.Controls.Add($label17);
$CaptureImage.Controls.Add($TxtBoxNomWIM);
$CaptureImage.Controls.Add($LblDescriptionWIM);
$CaptureImage.Controls.Add($TxtBoxCaptureDescriptionWIM);
$CaptureImage.Controls.Add($ChkBoxCaptureVerifier);
$CaptureImage.Controls.Add($LblCompression);
$CaptureImage.Controls.Add($LblNomFichierWIM);
$CaptureImage.Controls.Add($LblDestination);
$CaptureImage.Controls.Add($LblSource);
$CaptureImage.Controls.Add($CmbBoxCaptureCompression);
$CaptureImage.Controls.Add($TxtBoxNomFichierDest);
$CaptureImage.Controls.Add($TxtBoxCaptureDestination);
$CaptureImage.Controls.Add($TxtBoxCaptureSource);
$CaptureImage.Controls.Add($BtnAjouter);
$CaptureImage.Controls.Add($BtnCreer);
$CaptureImage.Controls.Add($ParcourirDestination);
$CaptureImage.Controls.Add($BtnParcourirSource);
$CaptureImage.Location = New-Object System.Drawing.Point(4, 29);
$CaptureImage.Name = "CaptureImage";
$CaptureImage.Size = New-Object System.Drawing.Size(882, 257);
$CaptureImage.TabIndex = 7;
$CaptureImage.Text = "Capture Image";
$CaptureImage.UseVisualStyleBackColor = $true;
#
# label17
#
$label17.AutoSize = $true;
$label17.Location = New-Object System.Drawing.Point(3, 154);
$label17.Name = "label17";
$label17.Size = New-Object System.Drawing.Size(146, 20);
$label17.TabIndex = 16;
$label17.Text = "Nom (interne) WIM:";
#
# TxtBoxNomWIM
#
$TxtBoxNomWIM.Location = New-Object System.Drawing.Point(214, 145);
$TxtBoxNomWIM.Name = "TxtBoxNomWIM";
$TxtBoxNomWIM.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxNomWIM.TabIndex = 15;
#
# LblDescriptionWIM
#
$LblDescriptionWIM.AutoSize = $true;
$LblDescriptionWIM.Location = New-Object System.Drawing.Point(3, 186);
$LblDescriptionWIM.Name = "LblDescriptionWIM";
$LblDescriptionWIM.Size = New-Object System.Drawing.Size(193, 20);
$LblDescriptionWIM.TabIndex = 14;
$LblDescriptionWIM.Text = "Description (interne) WIM:";
#
# TxtBoxCaptureDescriptionWIM
#
$TxtBoxCaptureDescriptionWIM.Location = New-Object System.Drawing.Point(214, 177);
$TxtBoxCaptureDescriptionWIM.Name = "TxtBoxCaptureDescriptionWIM";
$TxtBoxCaptureDescriptionWIM.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptureDescriptionWIM.TabIndex = 13;
#
# ChkBoxCaptureVerifier
#
$ChkBoxCaptureVerifier.AutoSize = $true;
$ChkBoxCaptureVerifier.Location = New-Object System.Drawing.Point(379, 214);
$ChkBoxCaptureVerifier.Name = "ChkBoxCaptureVerifier";
$ChkBoxCaptureVerifier.Size = New-Object System.Drawing.Size(78, 24);
$ChkBoxCaptureVerifier.TabIndex = 12;
$ChkBoxCaptureVerifier.Text = "Vérifier";
$ChkBoxCaptureVerifier.UseVisualStyleBackColor = $true;
#
# LblCompression
#
$LblCompression.AutoSize = $true;
$LblCompression.Location = New-Object System.Drawing.Point(3, 220);
$LblCompression.Name = "LblCompression";
$LblCompression.Size = New-Object System.Drawing.Size(106, 20);
$LblCompression.TabIndex = 11;
$LblCompression.Text = "Compression:";
#
# LblNomFichierWIM
#
$LblNomFichierWIM.AutoSize = $true;
$LblNomFichierWIM.Location = New-Object System.Drawing.Point(3, 118);
$LblNomFichierWIM.Name = "LblNomFichierWIM";
$LblNomFichierWIM.Size = New-Object System.Drawing.Size(211, 20);
$LblNomFichierWIM.TabIndex = 10;
$LblNomFichierWIM.Text = "Nom fichier WIM destination:";
#
# LblDestination
#
$LblDestination.AutoSize = $true;
$LblDestination.Location = New-Object System.Drawing.Point(3, 76);
$LblDestination.Name = "LblDestination";
$LblDestination.Size = New-Object System.Drawing.Size(186, 20);
$LblDestination.TabIndex = 9;
$LblDestination.Text = "Dossier WIM destination:";
#
# LblSource
#
$LblSource.AutoSize = $true;
$LblSource.Location = New-Object System.Drawing.Point(3, 31);
$LblSource.Name = "LblSource";
$LblSource.Size = New-Object System.Drawing.Size(119, 20);
$LblSource.TabIndex = 8;
$LblSource.Text = "Dossier source:";
#
# CmbBoxCaptureCompression
#
$CmbBoxCaptureCompression.FormattingEnabled = $true;
$CmbBoxCaptureCompression.Items.AddRange(@(
"none",
"fast",
"max"))
$CmbBoxCaptureCompression.Location = New-Object System.Drawing.Point(214, 209);
$CmbBoxCaptureCompression.Name = "CmbBoxCaptureCompression";
$CmbBoxCaptureCompression.Size = New-Object System.Drawing.Size(121, 28);
$CmbBoxCaptureCompression.TabIndex = 7;
#
# TxtBoxNomFichierDest
#
$TxtBoxNomFichierDest.Location = New-Object System.Drawing.Point(214, 112);
$TxtBoxNomFichierDest.Name = "TxtBoxNomFichierDest";
$TxtBoxNomFichierDest.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxNomFichierDest.TabIndex = 6;
#
# TxtBoxCaptureDestination
#
$TxtBoxCaptureDestination.Location = New-Object System.Drawing.Point(214, 70);
$TxtBoxCaptureDestination.Name = "TxtBoxCaptureDestination";
$TxtBoxCaptureDestination.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptureDestination.TabIndex = 5;
#
# TxtBoxCaptureSource
#
$TxtBoxCaptureSource.Location = New-Object System.Drawing.Point(214, 28);
$TxtBoxCaptureSource.Name = "TxtBoxCaptureSource";
$TxtBoxCaptureSource.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptureSource.TabIndex = 4;
#
# BtnAjouter
#
$BtnAjouter.Location = New-Object System.Drawing.Point(690, 115);
$BtnAjouter.Name = "BtnAjouter";
$BtnAjouter.Size = New-Object System.Drawing.Size(98, 42);
$BtnAjouter.TabIndex = 3;
$BtnAjouter.Text = "Ajouter";
$BtnAjouter.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'ajouter une image dans un wim existant
###########################################################################################################################

function OnClick_BtnAjouter {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAjouter.Add_Click n'est pas implémenté.");

  if ($TxtBoxCaptureSource.Text -eq ""){                             # fichier source présent
     [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un dossier source.");
  }
  else{
     if ($TxtBoxCaptureDestination.Text -eq ""){                    # fichier destination présent
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier destination.");
     }
     else{
        if ($TxtBoxNomFichierDest.Text -eq ""){                 # nom fichier WIM renseigné
           [void][System.Windows.Forms.MessageBox]::Show("Vous devez saisir un nom pour le fichier WIM de destination.");
        }
        else{
           if ($TxtBoxCaptureDescriptionWIM.Text -eq ""){
               [void][System.Windows.Forms.MessageBox]::Show("Vous devez renseigner le champ description WIM.");
           }
           else{
              $StrSource = $TxtBoxCaptureSource.Text;               # non utile, mémorise source
              $StrDest = $TxtBoxCaptureDestination.Text;            # non utile, mémorise destination
              $StrName = $TxtBoxCaptureDescriptionWIM.Text;         # non utile, mémorise nom fichier
              $StrCompression = $CmbBoxCaptureCompression.Text;     # non utile, mémorise niveau de compression
              
              if ([System.IO.Path]::GetExtension($TxtBoxNomFichierDest.Text.ToUpper()) -ne ".WIM"){
                $TxtBoxNomFichierDest.Text = $TxtBoxNomFichierDest.Text + ".wim";
              }
              $StrDISMArguments = "/Append-Image /ImageFile:" + "`"" + $TxtBoxCaptureDestination.Text + "\" + $TxtBoxNomFichierDest.Text + "`"" + " /CaptureDir:" + "`"" + $TxtBoxCaptureSource.Text + "`"" + " /Name:" + "`"" + $TxtBoxNomWIM.Text + "`"" + " /Description:" + "`"" + $TxtBoxCaptureDescriptionWIM.Text + "`"";
              if ($ChkBoxCaptureVerifier.Checked -eq $true){
                $StrDISMArguments = $StrDISMArguments + " /Verify";
              }
              $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
              $TxtBoxOutput.Text = $global:StrOutput;
              $TxtBoxOutput.Refresh();
              write-host "OnClick_BtnAjouter (avant), contenu de la variable: "$global:StrOutput;
              OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
              write-host "OnClick_BtnAjouter (après), contenu de la variable: "$global:StrOutput;
              $TxtBoxOutput.Text = $global:StrOutput;
              $TxtBoxOutput.Refresh();
           }
        }
     }
  }
}

$BtnAjouter.Add_Click( { OnClick_BtnAjouter } );

#
# BtnCreer
#
$BtnCreer.Location = New-Object System.Drawing.Point(690, 31);
$BtnCreer.Name = "BtnCreer";
$BtnCreer.Size = New-Object System.Drawing.Size(98, 46);
$BtnCreer.TabIndex = 2;
$BtnCreer.Text = "Créer";
$BtnCreer.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de créer une image wim, fonction Capture Image
###########################################################################################################################

function OnClick_BtnCreer {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnCreer.Add_Click n'est pas implémenté.");

  if ($TxtBoxCaptureSource.Text -eq ""){                                    # fichier source présent
     [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un dossier source.");
  }
  else{
     if ($TxtBoxCaptureDestination.Text -eq ""){                            # fichier destination présent
         [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier destination.");
     }
     else{
        if ($TxtBoxNomFichierDest.Text -eq ""){                             # nom fichier renseigné
            [void][System.Windows.Forms.MessageBox]::Show("Vous devez saisir un nom pour le fichier WIM de destination.");
        }
        else{
           if ($TxtBoxCaptureDescriptionWIM.Text -eq ""){
              [void][System.Windows.Forms.MessageBox]::Show("Vous devez renseigner le champ description WIM.");
           }
           else{
              $StrSource = $TxtBoxCaptureSource.Text;
              $StrDest = $TxtBoxCaptureDestination.Text;
              $StrName = $TxtBoxNomFichierDest.Text;
              $StrCompression = $CmbBoxCaptureCompression.Text;

              if ($StrSource.Length -ne 3){                               # pas d'encadrement du lecteur logique via double côtes
                $StrSource = "`"" + $StrSource + "`"";             # cas particulier dism erreur 123
              }
              if ([System.IO.Path]::GetExtension($TxtBoxNomFichierDest.Text.ToUpper()) -ne ".WIM"){
                $TxtBoxNomFichierDest.Text = $TxtBoxNomFichierDest.Text + ".wim";
              }
              if ($ChkBoxCaptureVerifier.Checked -eq $true){       # arguments avec option de vérification
                 $StrDISMArguments = "/Capture-Image /ImageFile:" + "`"" + $StrDest + "\" + $StrName + "`"" + " /CaptureDir:" + $StrSource + " /Name:" + "`"" + $TxtBoxNomWIM.Text + "`"" + " /Description:" + "`"" + $TxtBoxCaptureDescriptionWIM.Text + "`"" + " /Compress:" + $StrCompression + " /Verify";
              }
              else{
                 $StrDISMArguments = "/Capture-Image /ImageFile:" + "`"" + $StrDest + "\" + $StrName + "`"" + " /CaptureDir:" + $StrSource + " /Name:" + "`"" + $TxtBoxNomWIM.Text + "`"" + " /Description:" + "`"" + $TxtBoxCaptureDescriptionWIM.Text + "`"" + " /Compress:" + $StrCompression;
              }

              $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
              $TxtBoxOutput.Text = $global:StrOutput;
              $TxtBoxOutput.Refresh();
              write-host "OnClick_BtnCreer (avant), contenu de la variable: "$global:StrOutput;
              OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
              write-host "OnClick_BtnCreer (après), contenu de la variable: "$global:StrOutput;
              $TxtBoxOutput.Text = $global:StrOutput;
              $TxtBoxOutput.Refresh();
           }
        }
     }
  }
}

$BtnCreer.Add_Click( { OnClick_BtnCreer } );

#
# ParcourirDestination
#
$ParcourirDestination.Location = New-Object System.Drawing.Point(531, 70);
$ParcourirDestination.Name = "ParcourirDestination";
$ParcourirDestination.Size = New-Object System.Drawing.Size(96, 26);
$ParcourirDestination.TabIndex = 1;
$ParcourirDestination.Text = "Parcourir";
$ParcourirDestination.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier destination
###########################################################################################################################

function OnClick_ParcourirDestination {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement ParcourirDestination.Add_Click n'est pas implémenté.");

   # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                        # à partir du dossier c:\
   }
 
   $FolderBrowser.ShowDialog();                                  # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxCaptureDestination.Text = $FolderBrowser.SelectedPath; # récupére le fichier sélectionné par l'utilisateur   
}   

$ParcourirDestination.Add_Click( { OnClick_ParcourirDestination } );

#
# BtnParcourirSource
#
$BtnParcourirSource.Location = New-Object System.Drawing.Point(531, 28);
$BtnParcourirSource.Name = "BtnParcourirSource";
$BtnParcourirSource.Size = New-Object System.Drawing.Size(96, 26);
$BtnParcourirSource.TabIndex = 0;
$BtnParcourirSource.Text = "Parcourir";
$BtnParcourirSource.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier source
###########################################################################################################################

function OnClick_BtnParcourirSource{
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnParcourirSource.Add_Click n'est pas implémenté.");

   # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                     # à partir du dossier c:\
   }
 
   $FolderBrowser.ShowDialog();                               # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxCaptureSource.Text = $FolderBrowser.SelectedPath;   # récupére le fichier sélectionné par l'utilisateur
   $StrFolderName = $TxtBoxCaptureSource.Text;      
}

$BtnParcourirSource.Add_Click( { OnClick_BtnParcourirSource } );

#
# AppliqueImage
#
$AppliqueImage.Controls.Add($TxtBoxAppliquerImageTaille);
$AppliqueImage.Controls.Add($label14);
$AppliqueImage.Controls.Add($TxtBoxAppliquerImageDescription);
$AppliqueImage.Controls.Add($label15);
$AppliqueImage.Controls.Add($TxtBoxAppliquerImageNom);
$AppliqueImage.Controls.Add($label16);
$AppliqueImage.Controls.Add($ChkBoxApplyVerifier);
$AppliqueImage.Controls.Add($label5);
$AppliqueImage.Controls.Add($CmbBoxApplyIndex);
$AppliqueImage.Controls.Add($LblDestinationBis);
$AppliqueImage.Controls.Add($LblSourceBis);
$AppliqueImage.Controls.Add($TxtBoxApplyDestination);
$AppliqueImage.Controls.Add($BtnAppliquerImage);
$AppliqueImage.Controls.Add($BtnApplyParcourirDestination);
$AppliqueImage.Controls.Add($TxtBoxApplySource);
$AppliqueImage.Controls.Add($BtnApplyParcourirSource);
$AppliqueImage.Location = New-Object System.Drawing.Point(4, 29);
$AppliqueImage.Name = "AppliqueImage";
$AppliqueImage.Size = New-Object System.Drawing.Size(882, 257);
$AppliqueImage.TabIndex = 8;
$AppliqueImage.Text = "Appliquer Image";
$AppliqueImage.UseVisualStyleBackColor = $true;
#
# TxtBoxAppliquerImageTaille
#
$TxtBoxAppliquerImageTaille.Enabled = $false;
$TxtBoxAppliquerImageTaille.Location = New-Object System.Drawing.Point(112, 196);
$TxtBoxAppliquerImageTaille.Name = "TxtBoxAppliquerImageTaille";
$TxtBoxAppliquerImageTaille.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxAppliquerImageTaille.TabIndex = 26;
#
# label14
#
$label14.AutoSize = $true;
$label14.Location = New-Object System.Drawing.Point(12, 196);
$label14.Name = "label14";
$label14.Size = New-Object System.Drawing.Size(49, 20);
$label14.TabIndex = 25;
$label14.Text = "Taille:";
#
# TxtBoxAppliquerImageDescription
#
$TxtBoxAppliquerImageDescription.Enabled = $false;
$TxtBoxAppliquerImageDescription.Location = New-Object System.Drawing.Point(112, 164);
$TxtBoxAppliquerImageDescription.Name = "TxtBoxAppliquerImageDescription";
$TxtBoxAppliquerImageDescription.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxAppliquerImageDescription.TabIndex = 24;
#
# label15
#
$label15.AutoSize = $true;
$label15.Location = New-Object System.Drawing.Point(12, 167);
$label15.Name = "label15";
$label15.Size = New-Object System.Drawing.Size(93, 20);
$label15.TabIndex = 23;
$label15.Text = "Description:";
#
# TxtBoxAppliquerImageNom
#
$TxtBoxAppliquerImageNom.Enabled = $false;
$TxtBoxAppliquerImageNom.Location = New-Object System.Drawing.Point(112, 132);
$TxtBoxAppliquerImageNom.Name = "TxtBoxAppliquerImageNom";
$TxtBoxAppliquerImageNom.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxAppliquerImageNom.TabIndex = 22;
#
# label16
#
$label16.AutoSize = $true;
$label16.Location = New-Object System.Drawing.Point(12, 135);
$label16.Name = "label16";
$label16.Size = New-Object System.Drawing.Size(46, 20);
$label16.TabIndex = 21;
$label16.Text = "Nom:";
#
# ChkBoxApplyVerifier
#
$ChkBoxApplyVerifier.AutoSize = $true;
$ChkBoxApplyVerifier.Location = New-Object System.Drawing.Point(608, 74);
$ChkBoxApplyVerifier.Name = "ChkBoxApplyVerifier";
$ChkBoxApplyVerifier.Size = New-Object System.Drawing.Size(78, 24);
$ChkBoxApplyVerifier.TabIndex = 9;
$ChkBoxApplyVerifier.Text = "Verifier";
$ChkBoxApplyVerifier.UseVisualStyleBackColor = $true;
#
# label5
#
$label5.AutoSize = $true;
$label5.Location = New-Object System.Drawing.Point(538, 43);
$label5.Name = "label5";
$label5.Size = New-Object System.Drawing.Size(52, 20);
$label5.TabIndex = 8;
$label5.Text = "Index:";
#
# CmbBoxApplyIndex
#
$CmbBoxApplyIndex.FormattingEnabled = $true;
$CmbBoxApplyIndex.Location = New-Object System.Drawing.Point(608, 40);
$CmbBoxApplyIndex.Name = "CmbBoxApplyIndex";
$CmbBoxApplyIndex.Size = New-Object System.Drawing.Size(57, 28);
$CmbBoxApplyIndex.TabIndex = 7;

###########################################################################################################################
# Permet de mettre les champs d'informations pour l'utilisateur
###########################################################################################################################

function OnSelectedIndexChanged_CmbBoxApplyIndex {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement CmbBoxApplyIndex.Add_SelectedIndexChanged n'est pas implémenté.");

  $TxtBoxAppliquerImageNom.Text = $ListInfosWimAppliquerImage[$CmbBoxApplyIndex.SelectedIndex].Nom_Wim;
  $TxtBoxAppliquerImageDescription.Text = $ListInfosWimAppliquerImage[$CmbBoxApplyIndex.SelectedIndex].Description_Wim;
  $TxtBoxAppliquerImageTaille.Text = $ListInfosWimAppliquerImage[$CmbBoxApplyIndex.SelectedIndex].Taille_Wim;
}

$CmbBoxApplyIndex.Add_SelectedIndexChanged( { OnSelectedIndexChanged_CmbBoxApplyIndex } );

#
# LblDestinationBis
#
$LblDestinationBis.AutoSize = $true;
$LblDestinationBis.Location = New-Object System.Drawing.Point(8, 93);
$LblDestinationBis.Name = "LblDestinationBis";
$LblDestinationBis.Size = New-Object System.Drawing.Size(94, 20);
$LblDestinationBis.TabIndex = 6;
$LblDestinationBis.Text = "Destination:";
#
# LblSourceBis
#
$LblSourceBis.AutoSize = $true;
$LblSourceBis.Location = New-Object System.Drawing.Point(8, 43);
$LblSourceBis.Name = "LblSourceBis";
$LblSourceBis.Size = New-Object System.Drawing.Size(64, 20);
$LblSourceBis.TabIndex = 5;
$LblSourceBis.Text = "Source:";
#
# TxtBoxApplyDestination
#
$TxtBoxApplyDestination.Location = New-Object System.Drawing.Point(112, 87);
$TxtBoxApplyDestination.Name = "TxtBoxApplyDestination";
$TxtBoxApplyDestination.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxApplyDestination.TabIndex = 4;
#
# BtnAppliquerImage
#
$BtnAppliquerImage.Location = New-Object System.Drawing.Point(723, 43);
$BtnAppliquerImage.Name = "BtnAppliquerImage";
$BtnAppliquerImage.Size = New-Object System.Drawing.Size(136, 53);
$BtnAppliquerImage.TabIndex = 3;
$BtnAppliquerImage.Text = "Appliquer Image";
$BtnAppliquerImage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'appliquer une image préalablement sélectionné vers un dossier sélectionné comme destination
###########################################################################################################################

function OnClick_BtnAppliquerImage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAppliquerImage.Add_Click n'est pas implémenté.");

  [String]$ChaineFichierSource;                                          # chemin complet et nom du fichier WIM source
  [String]$ChaineDossierDest;                                            # chemin complet du dossier où appliquer le WIM
  [String]$ChaineIndexWIM;                                               # Index WIM qui sera appliqué

  if ($TxtBoxApplySource.Text -eq ""){                                  # fichier WIM source référencé ?
     [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier source WIM.");
  }
  else{
     if ($TxtBoxApplyDestination.Text -eq ""){                          # dossier destination référencé ?
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un dossier destination.");
     } 
     else{
        if ($CmbBoxApplyIndex.Text -eq ""){                             # index image WIM référencé ?
           [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un numéro d'index.");
        }
        else{
           $StrFolderName = $TxtBoxApplyDestination.Text;                # non utile mémorise le dossier destination, dans un but de futur utilisation
           $ChaineFichierSource = "`"" + $TxtBoxApplySource.Text + "`""; # encadrement de la chaine pour les caractères espaces
           $ChaineDossierDest = $TxtBoxApplyDestination.Text;            # pas d'encadrement sur lecteur logique évite l'erreur 123
           if ($ChaineDossierDest.Length -ne 3){
              $ChaineDossierDest = "`"" + $ChaineDossierDest + "`"";
           }
           $ChaineIndexWIM = $CmbBoxApplyIndex.Text;                     # Numéro Index WIM à appliquer
           if ($ChkBoxApplyVerifier.Checked -eq $true){                 # paramètres arguments ligne de commande avec vérification
              $StrDISMArguments = "/Apply-Image /ImageFile:" + $ChaineFichierSource + " /Index:" + $ChaineIndexWIM + " /ApplyDir:" + $ChaineDossierDest + " /Verify";
           }
           else{                                                        # paramètres arguments ligne de commande sans vérification
              $StrDISMArguments = "/Apply-Image /ImageFile:" + $ChaineFichierSource + " /Index:" + $ChaineIndexWIM + " /ApplyDir:" + $ChaineDossierDest;
           }
           $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
           $TxtBoxOutput.Text = $global:StrOutput;
           $TxtBoxOutput.Refresh();
           write-host "OnClick_BtnAppliquerImage (avant), contenu de la variable: "$global:StrOutput;
           OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
           write-host "OnClick_BtnAppliquerImage (après), contenu de la variable: "$global:StrOutput;
           $TxtBoxOutput.Text = $global:StrOutput;
           $TxtBoxOutput.Refresh();
        }
     }
  }
}

$BtnAppliquerImage.Add_Click( { OnClick_BtnAppliquerImage } );

#
# BtnApplyParcourirDestination
#
$BtnApplyParcourirDestination.Location = New-Object System.Drawing.Point(441, 87);
$BtnApplyParcourirDestination.Name = "BtnApplyParcourirDestination";
$BtnApplyParcourirDestination.Size = New-Object System.Drawing.Size(89, 26);
$BtnApplyParcourirDestination.TabIndex = 2;
$BtnApplyParcourirDestination.Text = "Parcourir";
$BtnApplyParcourirDestination.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier destination fonction appliquer image
###########################################################################################################################

function OnClick_BtnApplyParcourirDestination {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnApplyParcourirDestination.Add_Click n'est pas implémenté.");

  # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                      # à partir du dossier c:\
   }
 
   $FolderBrowser.ShowDialog();                                # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxApplyDestination.Text = $FolderBrowser.SelectedPath; # récupére le fichier sélectionné par l'utilisateur 
}

$BtnApplyParcourirDestination.Add_Click( { OnClick_BtnApplyParcourirDestination } );

#
# TxtBoxApplySource
#
$TxtBoxApplySource.Location = New-Object System.Drawing.Point(112, 40);
$TxtBoxApplySource.Name = "TxtBoxApplySource";
$TxtBoxApplySource.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxApplySource.TabIndex = 1;
#
# BtnApplyParcourirSource
#
$BtnApplyParcourirSource.Location = New-Object System.Drawing.Point(441, 40);
$BtnApplyParcourirSource.Name = "BtnApplyParcourirSource";
$BtnApplyParcourirSource.Size = New-Object System.Drawing.Size(89, 26);
$BtnApplyParcourirSource.TabIndex = 0;
$BtnApplyParcourirSource.Text = "Parcourir";
$BtnApplyParcourirSource.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier source fonction appliquer image
###########################################################################################################################

function OnClick_BtnApplyParcourirSource {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnApplyParcourirSource.Add_Click n'est pas implémenté.");

  [int]$IdxFor;

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    Title = "Choisir un fichier WIM ouvrir"
    Filter = 'Fichier WIM (*.wim)|*.wim|Tous Fichiers (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxApplySource.Text = $FileBrowser.FileName;
  
    AfficheWimInfos "AppliquerImage_WimInfos.txt" $TxtBoxApplySource.Text;       # On passe les deux arguments 
    $CmbBoxApplyIndex.Items.Clear();                                             # efface le contenu de la combobox d'index
    write-host 'Dans OnClick_BtnChoisirWim, Type de la variable $ListInfosWimGestionMontage: '$ListInfosWimGestionMontage.gettype();
    MAJListeIndex "AppliquerImage_WimInfos.txt" $ListInfosWimAppliquerImage;     # Mise à jour des index
              
    for ($IdxFor = 1; $IdxFor -le $ListInfosWimAppliquerImage.Count; $IdxFor++){
       $CmbBoxApplyIndex.Items.Add($IdxFor);                                     # création interval index concernant le WIM
    }
  }
}

$BtnApplyParcourirSource.Add_Click( { OnClick_BtnApplyParcourirSource } );

#
# ExportImage
#
$ExportImage.Controls.Add($TxtBoxExportImageTaille);
$ExportImage.Controls.Add($LblExportImageTaille);
$ExportImage.Controls.Add($TxtBoxExportImageDescription);
$ExportImage.Controls.Add($LblExportImageDescription);
$ExportImage.Controls.Add($TxtBoxExportImageNom);
$ExportImage.Controls.Add($LblExportImageNom);
$ExportImage.Controls.Add($LblExportName);
$ExportImage.Controls.Add($TxtBoxNomFichier);
$ExportImage.Controls.Add($ChkBoxExportCheckIntegrity);
$ExportImage.Controls.Add($ChkBoxExportWimBoot);
$ExportImage.Controls.Add($ChkBoxExportBootable);
$ExportImage.Controls.Add($label9);
$ExportImage.Controls.Add($CmbBoxExportCompression);
$ExportImage.Controls.Add($label6);
$ExportImage.Controls.Add($CmbBoxExportIndex);
$ExportImage.Controls.Add($LblExportDestination);
$ExportImage.Controls.Add($LblExportSource);
$ExportImage.Controls.Add($TxtBoxExportDestination);
$ExportImage.Controls.Add($BtnExportImage);
$ExportImage.Controls.Add($BtnExportChoisirDossier);
$ExportImage.Controls.Add($TxtBoxExportSourceFichier);
$ExportImage.Controls.Add($BtnExportChoisirFichier);
$ExportImage.Location = New-Object System.Drawing.Point(4, 29);
$ExportImage.Name = "ExportImage";
$ExportImage.Size = New-Object System.Drawing.Size(882, 257);
$ExportImage.TabIndex = 9;
$ExportImage.Text = "Export Image";
$ExportImage.UseVisualStyleBackColor = $true;
#
# TxtBoxExportImageTaille
#
$TxtBoxExportImageTaille.Enabled = $false;
$TxtBoxExportImageTaille.Location = New-Object System.Drawing.Point(133, 201);
$TxtBoxExportImageTaille.Name = "TxtBoxExportImageTaille";
$TxtBoxExportImageTaille.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxExportImageTaille.TabIndex = 39;
#
# LblExportImageTaille
#
$LblExportImageTaille.AutoSize = $true;
$LblExportImageTaille.Location = New-Object System.Drawing.Point(33, 201);
$LblExportImageTaille.Name = "LblExportImageTaille";
$LblExportImageTaille.Size = New-Object System.Drawing.Size(49, 20);
$LblExportImageTaille.TabIndex = 38;
$LblExportImageTaille.Text = "Taille:";
#
# TxtBoxExportImageDescription
#
$TxtBoxExportImageDescription.Enabled = $false;
$TxtBoxExportImageDescription.Location = New-Object System.Drawing.Point(133, 169);
$TxtBoxExportImageDescription.Name = "TxtBoxExportImageDescription";
$TxtBoxExportImageDescription.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxExportImageDescription.TabIndex = 37;
#
# LblExportImageDescription
#
$LblExportImageDescription.AutoSize = $true;
$LblExportImageDescription.Location = New-Object System.Drawing.Point(33, 172);
$LblExportImageDescription.Name = "LblExportImageDescription";
$LblExportImageDescription.Size = New-Object System.Drawing.Size(93, 20);
$LblExportImageDescription.TabIndex = 36;
$LblExportImageDescription.Text = "Description:";
#
# TxtBoxExportImageNom
#
$TxtBoxExportImageNom.Enabled = $false;
$TxtBoxExportImageNom.Location = New-Object System.Drawing.Point(133, 137);
$TxtBoxExportImageNom.Name = "TxtBoxExportImageNom";
$TxtBoxExportImageNom.Size = New-Object System.Drawing.Size(418, 26);
$TxtBoxExportImageNom.TabIndex = 35;
#
# LblExportImageNom
#
$LblExportImageNom.AutoSize = $true;
$LblExportImageNom.Location = New-Object System.Drawing.Point(33, 140);
$LblExportImageNom.Name = "LblExportImageNom";
$LblExportImageNom.Size = New-Object System.Drawing.Size(46, 20);
$LblExportImageNom.TabIndex = 34;
$LblExportImageNom.Text = "Nom:";
#
# LblExportName
#
$LblExportName.AutoSize = $true;
$LblExportName.Location = New-Object System.Drawing.Point(28, 93);
$LblExportName.Name = "LblExportName";
$LblExportName.Size = New-Object System.Drawing.Size(92, 20);
$LblExportName.TabIndex = 25;
$LblExportName.Text = "Nom fichier:";
#
# TxtBoxNomFichier
#
$TxtBoxNomFichier.Location = New-Object System.Drawing.Point(132, 90);
$TxtBoxNomFichier.Name = "TxtBoxNomFichier";
$TxtBoxNomFichier.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxNomFichier.TabIndex = 24;
#
# ChkBoxExportCheckIntegrity
#
$ChkBoxExportCheckIntegrity.AutoSize = $true;
$ChkBoxExportCheckIntegrity.Location = New-Object System.Drawing.Point(634, 172);
$ChkBoxExportCheckIntegrity.Name = "ChkBoxExportCheckIntegrity";
$ChkBoxExportCheckIntegrity.Size = New-Object System.Drawing.Size(134, 24);
$ChkBoxExportCheckIntegrity.TabIndex = 22;
$ChkBoxExportCheckIntegrity.Text = "/CheckIntegrity";
$ChkBoxExportCheckIntegrity.UseVisualStyleBackColor = $true;
#
# ChkBoxExportWimBoot
#
$ChkBoxExportWimBoot.AutoSize = $true;
$ChkBoxExportWimBoot.Location = New-Object System.Drawing.Point(758, 137);
$ChkBoxExportWimBoot.Name = "ChkBoxExportWimBoot";
$ChkBoxExportWimBoot.Size = New-Object System.Drawing.Size(97, 24);
$ChkBoxExportWimBoot.TabIndex = 21;
$ChkBoxExportWimBoot.Text = "/WimBoot";
$ChkBoxExportWimBoot.UseVisualStyleBackColor = $true;
#
# ChkBoxExportBootable
#
$ChkBoxExportBootable.AutoSize = $true;
$ChkBoxExportBootable.Location = New-Object System.Drawing.Point(633, 137);
$ChkBoxExportBootable.Name = "ChkBoxExportBootable";
$ChkBoxExportBootable.Size = New-Object System.Drawing.Size(96, 24);
$ChkBoxExportBootable.TabIndex = 20;
$ChkBoxExportBootable.Text = "/Bootable";
$ChkBoxExportBootable.UseVisualStyleBackColor = $true;
#
# label9
#
$label9.AutoSize = $true;
$label9.Location = New-Object System.Drawing.Point(630, 96);
$label9.Name = "label9";
$label9.Size = New-Object System.Drawing.Size(106, 20);
$label9.TabIndex = 19;
$label9.Text = "Compression:";
#
# CmbBoxExportCompression
#
$CmbBoxExportCompression.FormattingEnabled = $true;
$CmbBoxExportCompression.Items.AddRange(@(
"fast",
"max",
"none",
"recovery"))
$CmbBoxExportCompression.Location = New-Object System.Drawing.Point(742, 93);
$CmbBoxExportCompression.Name = "CmbBoxExportCompression";
$CmbBoxExportCompression.Size = New-Object System.Drawing.Size(132, 28);
$CmbBoxExportCompression.TabIndex = 18;
#
# label6
#
$label6.AutoSize = $true;
$label6.Location = New-Object System.Drawing.Point(486, 96);
$label6.Name = "label6";
$label6.Size = New-Object System.Drawing.Size(52, 20);
$label6.TabIndex = 17;
$label6.Text = "Index:";
#
# CmbBoxExportIndex
#
$CmbBoxExportIndex.FormattingEnabled = $true;
$CmbBoxExportIndex.Location = New-Object System.Drawing.Point(544, 93);
$CmbBoxExportIndex.Name = "CmbBoxExportIndex";
$CmbBoxExportIndex.Size = New-Object System.Drawing.Size(57, 28);
$CmbBoxExportIndex.TabIndex = 16;

###########################################################################################################################
# Permet d'afficher les informations utilisateur pour un index sélectionné fonction Export Image
###########################################################################################################################

function OnSelectedIndexChanged_CmbBoxExportIndex {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement CmbBoxExportIndex.Add_SelectedIndexChanged n'est pas implémenté.");

  $TxtBoxExportImageNom.Text = $ListInfosWimExportImage[$CmbBoxExportIndex.SelectedIndex].Nom_Wim;
  $TxtBoxExportImageDescription.Text = $ListInfosWimExportImage[$CmbBoxExportIndex.SelectedIndex].Description_Wim;
  $TxtBoxExportImageTaille.Text = $ListInfosWimExportImage[$CmbBoxExportIndex.SelectedIndex].Taille_Wim;
}

$CmbBoxExportIndex.Add_SelectedIndexChanged( { OnSelectedIndexChanged_CmbBoxExportIndex } );

#
# LblExportDestination
#
$LblExportDestination.AutoSize = $true;
$LblExportDestination.Location = New-Object System.Drawing.Point(28, 61);
$LblExportDestination.Name = "LblExportDestination";
$LblExportDestination.Size = New-Object System.Drawing.Size(94, 20);
$LblExportDestination.TabIndex = 15;
$LblExportDestination.Text = "Destination:";
#
# LblExportSource
#
$LblExportSource.AutoSize = $true;
$LblExportSource.Location = New-Object System.Drawing.Point(29, 29);
$LblExportSource.Name = "LblExportSource";
$LblExportSource.Size = New-Object System.Drawing.Size(64, 20);
$LblExportSource.TabIndex = 14;
$LblExportSource.Text = "Source:";
#
# TxtBoxExportDestination
#
$TxtBoxExportDestination.Location = New-Object System.Drawing.Point(132, 58);
$TxtBoxExportDestination.Name = "TxtBoxExportDestination";
$TxtBoxExportDestination.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxExportDestination.TabIndex = 13;
#
# BtnExportImage
#
$BtnExportImage.Location = New-Object System.Drawing.Point(650, 31);
$BtnExportImage.Name = "BtnExportImage";
$BtnExportImage.Size = New-Object System.Drawing.Size(136, 53);
$BtnExportImage.TabIndex = 12;
$BtnExportImage.Text = "Export Image";
$BtnExportImage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'exporter une image préalablement sélectionné d'un fichier esd (conversion en fichier wim)
###########################################################################################################################

function OnClick_BtnExportImage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportImage.Add_Click n'est pas implémenté.");
   
   [String]$FicSrc;
   [String]$FicDest;
   [String]$FicNom;
   [String]$Index;
   [String]$Compr;

   if ($TxtBoxExportSourceFichier.Text -eq ""){                          # fichier WIM source référencé ?
      [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier source esd ou WIM.");
   }
   else{
      if ($TxtBoxExportDestination.Text -eq ""){                         # dossier destination référencé ?
         [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un dossier destination.");
      }
      else{
         if ($TxtBoxNomFichier.Text -eq ""){
            [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un nom de fchier destination.");
         }
         else{
            if ($CmbBoxExportIndex.Text -eq ""){                          # index image WIM référencé ?
               [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un numéro d'index.");
            }
            else{
               if ($CmbBoxExportCompression.Text -eq ""){
                  [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un mode de compression.");
               }
               else{
                  $FicSrc = $TxtBoxExportSourceFichier.Text;
                  $FicDest = $TxtBoxExportDestination.Text;
                  $Index = $CmbBoxExportIndex.Text;
                  $Compr = $CmbBoxExportCompression.Text;

                  # ou peut aussi exporter en ESD au cas où....
                  #if (Path.GetExtension(TxtBoxNomFichier.Text.ToUpper()) != ".WIM") TxtBoxNomFichier.Text = TxtBoxNomFichier.Text + ".wim";
                  $FicNom = $TxtBoxNomFichier.Text;
                  $StrDISMArguments = "/Export-Image /SourceImageFile:" + "`"" + $FicSrc + "`"" + " /SourceIndex:" + $Index + " /DestinationImageFile:" + "`"" + $FicDest + "\" + $FicNom + "`"" + " /Compress:" + $Compr;

                  if ($ChkBoxExportBootable.Checked -eq $true){
                     $StrDISMArguments = $StrDISMArguments + " /Bootable";
                  }
                  
                  if ($ChkBoxExportWimBoot.Checked -eq $true){
                     $StrDISMArguments = $StrDISMArguments + " /WIMBoot";
                  }
                  
                  if ($ChkBoxExportCheckIntegrity.Checked -eq $true){
                     $StrDISMArguments = $StrDISMArguments + " /CheckIntegrity";
                  }
                  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
                  write-host 'Dans OnClick_BtnExportImage, valeur avant de $global:StrOutput:'$global:StrOutput;
                  $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
                  $TxtBoxOutput.Refresh();
                  write-host 'Dans OnClick_BtnExportImage, valeur de la variable $StrDISMArguments:'$StrDISMArguments;
                  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
                  write-host 'Dans OnClick_BtnExportImage, valeur après de $global:StrOutput:'$global:StrOutput;
                  $TxtBoxOutput.Text=$global:StrOutput;                                  # Affiche le résultat dans la console
                  $TxtBoxOutput.Refresh();
               }
            }
         }
      }
   }
}

$BtnExportImage.Add_Click( { OnClick_BtnExportImage } );

#
# BtnExportChoisirDossier
#
$BtnExportChoisirDossier.Location = New-Object System.Drawing.Point(464, 58);
$BtnExportChoisirDossier.Name = "BtnExportChoisirDossier";
$BtnExportChoisirDossier.Size = New-Object System.Drawing.Size(137, 26);
$BtnExportChoisirDossier.TabIndex = 11;
$BtnExportChoisirDossier.Text = "Choisir Dossier";
$BtnExportChoisirDossier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier destination fonction export image
###########################################################################################################################

function OnClick_BtnExportChoisirDossier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportChoisirDossier.Add_Click n'est pas implémenté.");

  # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                       # à partir du dossier c:\
   }
 
   [void]$FolderBrowser.ShowDialog();                           # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxExportDestination.Text=$FolderBrowser.SelectedPath;   # récupère la sélection de l'utilisateur
}

$BtnExportChoisirDossier.Add_Click( { OnClick_BtnExportChoisirDossier } );

#
# TxtBoxExportSourceFichier
#
$TxtBoxExportSourceFichier.Location = New-Object System.Drawing.Point(133, 26);
$TxtBoxExportSourceFichier.Name = "TxtBoxExportSourceFichier";
$TxtBoxExportSourceFichier.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxExportSourceFichier.TabIndex = 10;
#
# BtnExportChoisirFichier
#
$BtnExportChoisirFichier.Location = New-Object System.Drawing.Point(465, 26);
$BtnExportChoisirFichier.Name = "BtnExportChoisirFichier";
$BtnExportChoisirFichier.Size = New-Object System.Drawing.Size(136, 26);
$BtnExportChoisirFichier.TabIndex = 9;
$BtnExportChoisirFichier.Text = "Choisir Fichier";
$BtnExportChoisirFichier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de sélectionner le dossier source fonction export image
###########################################################################################################################

function OnClick_BtnExportChoisirFichier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportChoisirFichier.Add_Click n'est pas implémenté.");

  [int]$IdxFor;

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    Title = "Choisir un fichier source ESD à ouvrir"
    Filter = 'Fichier ESD (*.esd)|*.esd|Tous Fichiers (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxExportSourceFichier.Text = $FileBrowser.FileName;
  
    AfficheWimInfos "ExportImage_WimInfos.txt" $TxtBoxExportSourceFichier.Text; # On passe les deux arguments 
    $CmbBoxExportIndex.Items.Clear();                                           # efface le contenu de la combobox d'index
    write-host 'Dans OnClick_BtnChoisirWim, Type de la variable $ListInfosWimGestionMontage: '$ListInfosWimGestionMontage.gettype();
    MAJListeIndex "ExportImage_WimInfos.txt" $ListInfosWimExportImage;          # Mise à jour des index
              
    for ($IdxFor = 1; $IdxFor -le $ListInfosWimExportImage.Count; $IdxFor++){
       $CmbBoxExportIndex.Items.Add($IdxFor);                                   # création interval index concernant le WIM
    }
  }
}

$BtnExportChoisirFichier.Add_Click( { OnClick_BtnExportChoisirFichier } );

#
# GestionLangue
#
$GestionLangue.Controls.Add($BtnAllIntrlAppliquer);
$GestionLangue.Controls.Add($TxtBoxAllIntl);
$GestionLangue.Controls.Add($label7);
$GestionLangue.Controls.Add($BtnInfosLangue);
$GestionLangue.Location = New-Object System.Drawing.Point(4, 29);
$GestionLangue.Name = "GestionLangue";
$GestionLangue.Size = New-Object System.Drawing.Size(882, 257);
$GestionLangue.TabIndex = 10;
$GestionLangue.Text = "Gestion Langue";
$GestionLangue.UseVisualStyleBackColor = $true;
#
# BtnAllIntrlAppliquer
#
$BtnAllIntrlAppliquer.Location = New-Object System.Drawing.Point(375, 22);
$BtnAllIntrlAppliquer.Name = "BtnAllIntrlAppliquer";
$BtnAllIntrlAppliquer.Size = New-Object System.Drawing.Size(97, 26);
$BtnAllIntrlAppliquer.TabIndex = 3;
$BtnAllIntrlAppliquer.Text = "Appliquer";
$BtnAllIntrlAppliquer.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de modifier une langue par défaut
###########################################################################################################################

function OnClick_BtnAllIntrlAppliquer {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAllIntrlAppliquer.Add_Click n'est pas implémenté.");

  if ($TxtBoxAllIntl.Text -eq ""){
     [void][System.Windows.Forms.MessageBox]::Show("Vous devez renseigner le champ //Set-AllIntl.");
  }
  else{
    $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Set-AllIntl:" + $TxtBoxAllIntl.Text;
    $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
    $TxtBoxOutput.Text = $global:StrOutput;
    $TxtBoxOutput.Refresh();
    write-host "OnClick_BtnAllIntrlAppliquer (avant), contenu de la variable: "$global:StrOutput;
    OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
    write-host "OnClick_BtnAllIntrlAppliquer (après), contenu de la variable: "$global:StrOutput;
    $TxtBoxOutput.Text = $global:StrOutput;
    $TxtBoxOutput.Refresh();
  }
}

$BtnAllIntrlAppliquer.Add_Click( { OnClick_BtnAllIntrlAppliquer } );

#
# TxtBoxAllIntl
#
$TxtBoxAllIntl.Location = New-Object System.Drawing.Point(125, 22);
$TxtBoxAllIntl.Name = "TxtBoxAllIntl";
$TxtBoxAllIntl.Size = New-Object System.Drawing.Size(222, 26);
$TxtBoxAllIntl.TabIndex = 2;
#
# label7
#
$label7.AutoSize = $true;
$label7.Location = New-Object System.Drawing.Point(22, 25);
$label7.Name = "label7";
$label7.Size = New-Object System.Drawing.Size(86, 20);
$label7.TabIndex = 1;
$label7.Text = "/Set-AllIntl:";
#
# BtnInfosLangue
#
$BtnInfosLangue.Location = New-Object System.Drawing.Point(591, 19);
$BtnInfosLangue.Name = "BtnInfosLangue";
$BtnInfosLangue.Size = New-Object System.Drawing.Size(278, 33);
$BtnInfosLangue.TabIndex = 0;
$BtnInfosLangue.Text = "Information language (mode offline)";
$BtnInfosLangue.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'afficher les informations sur la langue
###########################################################################################################################

function OnClick_BtnInfosLangue {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnInfosLangue.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Get-Intl";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
     write-host "OnClick_BtnInfosLangue (avant), contenu de la variable: "$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host "OnClick_BtnInfosLangue (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
  }
}

$BtnInfosLangue.Add_Click( { OnClick_BtnInfosLangue } );

#
# ExportDriver
#
$ExportDriver.Controls.Add($BtnExportDriverOnline);
$ExportDriver.Controls.Add($label8);
$ExportDriver.Controls.Add($TxtBoxExportDossierDriverOnline);
$ExportDriver.Controls.Add($BtnExportDriverChoisirDossierOnline);
$ExportDriver.Controls.Add($BtnExportDriverOffline);
$ExportDriver.Controls.Add($LblExportChoisirDossier);
$ExportDriver.Controls.Add($TxtBoxExportDossierDriverOffline);
$ExportDriver.Controls.Add($BtnExportDriverChoisirDossierOffline);
$ExportDriver.Location = New-Object System.Drawing.Point(4, 29);
$ExportDriver.Name = "ExportDriver";
$ExportDriver.Size = New-Object System.Drawing.Size(882, 257);
$ExportDriver.TabIndex = 11;
$ExportDriver.Text = "Export Pilotes";
$ExportDriver.UseVisualStyleBackColor = $true;
#
# BtnExportDriverOnline
#
$BtnExportDriverOnline.Location = New-Object System.Drawing.Point(654, 162);
$BtnExportDriverOnline.Name = "BtnExportDriverOnline";
$BtnExportDriverOnline.Size = New-Object System.Drawing.Size(198, 60);
$BtnExportDriverOnline.TabIndex = 7;
$BtnExportDriverOnline.Text = "Export Driver Online";
$BtnExportDriverOnline.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'exporter les pilotes dans un dossier spécifier en mode OnLine
###########################################################################################################################

function OnClick_BtnExportDriverOnline {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportDriverOnline.Add_Click n'est pas implémenté.");

  if ($TxtBoxExportDossierDriverOnline.Text -eq ""){
     [void][System.Windows.Forms.MessageBox]::Show("Vous devez renseigner le champ Dossier (online).");
  }
  else{
     $StrDISMArguments = "/Online" + " /Export-Driver" + " /Destination:" + "`"" + $TxtBoxExportDossierDriverOnline.Text + "`"";
     $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
     write-host "OnClick_BtnInfosLangue (avant), contenu de la variable: "$global:StrOutput;
     OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
     write-host "OnClick_BtnInfosLangue (après), contenu de la variable: "$global:StrOutput;
     $TxtBoxOutput.Text = $global:StrOutput;
     $TxtBoxOutput.Refresh();
  }
}

$BtnExportDriverOnline.Add_Click( { OnClick_BtnExportDriverOnline } );

#
# label8
#
$label8.AutoSize = $true;
$label8.Location = New-Object System.Drawing.Point(8, 182);
$label8.Name = "label8";
$label8.Size = New-Object System.Drawing.Size(67, 20);
$label8.TabIndex = 6;
$label8.Text = "Dossier:";
#
# TxtBoxExportDossierDriverOnline
#
$TxtBoxExportDossierDriverOnline.Location = New-Object System.Drawing.Point(116, 176);
$TxtBoxExportDossierDriverOnline.Name = "TxtBoxExportDossierDriverOnline";
$TxtBoxExportDossierDriverOnline.Size = New-Object System.Drawing.Size(501, 26);
$TxtBoxExportDossierDriverOnline.TabIndex = 5;
#
# BtnExportDriverChoisirDossierOnline
#
$BtnExportDriverChoisirDossierOnline.Location = New-Object System.Drawing.Point(279, 217);
$BtnExportDriverChoisirDossierOnline.Name = "BtnExportDriverChoisirDossierOnline";
$BtnExportDriverChoisirDossierOnline.Size = New-Object System.Drawing.Size(150, 29);
$BtnExportDriverChoisirDossierOnline.TabIndex = 4;
$BtnExportDriverChoisirDossierOnline.Text = "Choisir Dossier";
$BtnExportDriverChoisirDossierOnline.UseVisualStyleBackColor = $true;

function OnClick_BtnExportDriverChoisirDossierOnline {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportDriverChoisirDossierOnline.Add_Click n'est pas implémenté.");

  # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                       # à partir du dossier c:\ (attention C: doit exister à vérifier...)
   }
   if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
      $TxtBoxExportDossierDriverOnline.Text = $FolderBrowser.SelectedPath;
   }
}

$BtnExportDriverChoisirDossierOnline.Add_Click( { OnClick_BtnExportDriverChoisirDossierOnline } );

#
# BtnExportDriverOffline
#
$BtnExportDriverOffline.Location = New-Object System.Drawing.Point(654, 27);
$BtnExportDriverOffline.Name = "BtnExportDriverOffline";
$BtnExportDriverOffline.Size = New-Object System.Drawing.Size(198, 60);
$BtnExportDriverOffline.TabIndex = 3;
$BtnExportDriverOffline.Text = "Export Driver Offline";
$BtnExportDriverOffline.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'exporter les drivers en mode OffLine dans un dossier spécifier
###########################################################################################################################

function OnClick_BtnExportDriverOffline{
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportDriverOffline.Add_Click n'est pas implémenté.");

  if ($WIMMounted -eq $false){                                    # WIM non monté
     [void][System.Windows.Forms.MessageBox]::Show("Aucun WIM Monté. Vous devez monter un WIM avant d'exécuter cette commande.");
  }
  else{
     if ($TxtBoxExportDossierDriverOffline.Text -eq ""){
        [void][System.Windows.Forms.MessageBox]::Show("Vous devez renseigner le champ Dossier (offline).");
     }
     else{
        $StrDISMArguments = "/Image:" + "`"" + $StrMountedImageLocation + "`"" + " /Export-Driver" + " /Destination:" + "`"" + $TxtBoxExportDossierDriverOffline.Text + "`"";
        $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
        write-host "OnClick_BtnExportDriverOffline (avant), contenu de la variable: "$global:StrOutput;
        OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
        write-host "OnClick_BtnExportDriverOffline (après), contenu de la variable: "$global:StrOutput;
        $TxtBoxOutput.Text = $global:StrOutput;
        $TxtBoxOutput.Refresh();
     }
  }

}

$BtnExportDriverOffline.Add_Click( { OnClick_BtnExportDriverOffline } );

#
# LblExportChoisirDossier
#
$LblExportChoisirDossier.AutoSize = $true;
$LblExportChoisirDossier.Location = New-Object System.Drawing.Point(8, 47);
$LblExportChoisirDossier.Name = "LblExportChoisirDossier";
$LblExportChoisirDossier.Size = New-Object System.Drawing.Size(67, 20);
$LblExportChoisirDossier.TabIndex = 2;
$LblExportChoisirDossier.Text = "Dossier:";
#
# TxtBoxExportDossierDriverOffline
#
$TxtBoxExportDossierDriverOffline.Location = New-Object System.Drawing.Point(116, 41);
$TxtBoxExportDossierDriverOffline.Name = "TxtBoxExportDossierDriverOffline";
$TxtBoxExportDossierDriverOffline.Size = New-Object System.Drawing.Size(501, 26);
$TxtBoxExportDossierDriverOffline.TabIndex = 1;
#
# BtnExportDriverChoisirDossierOffline
#
$BtnExportDriverChoisirDossierOffline.Location = New-Object System.Drawing.Point(279, 82);
$BtnExportDriverChoisirDossierOffline.Name = "BtnExportDriverChoisirDossierOffline";
$BtnExportDriverChoisirDossierOffline.Size = New-Object System.Drawing.Size(150, 29);
$BtnExportDriverChoisirDossierOffline.TabIndex = 0;
$BtnExportDriverChoisirDossierOffline.Text = "Choisir Dossier";
$BtnExportDriverChoisirDossierOffline.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet le choix du répertoire pour l'exportation des drivers on mode OffLine
###########################################################################################################################

function OnClick_BtnExportDriverChoisirDossierOffline {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnExportDriverChoisirDossierOffline.Add_Click n'est pas implémenté.");

   # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                       # à partir du dossier c:\ (attention C: doit exister à vérifier...)
   }
   if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
      $TxtBoxExportDossierDriverOffline.Text = $FolderBrowser.SelectedPath;
   }
}

$BtnExportDriverChoisirDossierOffline.Add_Click( { OnClick_BtnExportDriverChoisirDossierOffline } );

#
# DecoupeImage
#
$DecoupeImage.Controls.Add($BtnDecoupeChoisirFichier);
$DecoupeImage.Controls.Add($BtnDecoupeChoisirDossier);
$DecoupeImage.Controls.Add($LblDecoupeDossierDestination);
$DecoupeImage.Controls.Add($TxtBoxDecoupeDossierDestination);
$DecoupeImage.Controls.Add($btnDecoupeImage);
$DecoupeImage.Controls.Add($ChkBoxDecoupeCheckIntegrity);
$DecoupeImage.Controls.Add($LblDecoupeTailleFichier);
$DecoupeImage.Controls.Add($TxtBoxDecoupeTailleFichier);
$DecoupeImage.Controls.Add($LblDecoupeNomFichierSWM);
$DecoupeImage.Controls.Add($LblDecoupeFichierWim);
$DecoupeImage.Controls.Add($TxtBoxDecoupeFichierSWM);
$DecoupeImage.Controls.Add($TxtBoxDecoupeFichierWIM);
$DecoupeImage.Location = New-Object System.Drawing.Point(4, 29);
$DecoupeImage.Name = "DecoupeImage";
$DecoupeImage.Size = New-Object System.Drawing.Size(882, 257);
$DecoupeImage.TabIndex = 12;
$DecoupeImage.Text = "Découper Image";
$DecoupeImage.UseVisualStyleBackColor = $true;
#
# BtnDecoupeChoisirFichier
#
$BtnDecoupeChoisirFichier.Location = New-Object System.Drawing.Point(498, 26);
$BtnDecoupeChoisirFichier.Name = "BtnDecoupeChoisirFichier";
$BtnDecoupeChoisirFichier.Size = New-Object System.Drawing.Size(136, 26);
$BtnDecoupeChoisirFichier.TabIndex = 40;
$BtnDecoupeChoisirFichier.Text = "Choisir Fichier";
$BtnDecoupeChoisirFichier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet De choisir le fichier WIM à découper
###########################################################################################################################

function OnClick_BtnDecoupeChoisirFichier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDecoupeChoisirFichier.Add_Click n'est pas implémenté.");

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = 'C:\'
    Title = 'Choisir un fichier WIM à ouvrir'
    Filter = 'Image Wim (*.wim)|*.wim'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxDecoupeFichierWIM.Text = $FileBrowser.FileName;     # Affiche le résultat de la sélection dans le champ TxtFichierWim
  }
}

$BtnDecoupeChoisirFichier.Add_Click( { OnClick_BtnDecoupeChoisirFichier } );

#
# BtnDecoupeChoisirDossier
#
$BtnDecoupeChoisirDossier.Location = New-Object System.Drawing.Point(498, 64);
$BtnDecoupeChoisirDossier.Name = "BtnDecoupeChoisirDossier";
$BtnDecoupeChoisirDossier.Size = New-Object System.Drawing.Size(136, 26);
$BtnDecoupeChoisirDossier.TabIndex = 39;
$BtnDecoupeChoisirDossier.Text = "Choisir Dossier";
$BtnDecoupeChoisirDossier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet De choisir le dossier de stockage du WIM découper
###########################################################################################################################

function OnClick_BtnDecoupeChoisirDossier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDecoupeChoisirDossier.Add_Click n'est pas implémenté.");

   # définit un objet FolderBrowser
   $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
     RootFolder=[System.Environment+SpecialFolder]'MyComputer'
     SelectedPath = 'C:\'                                                   # à partir du dossier c:\
   }
   [void]$FolderBrowser.ShowDialog();                                        # Affiche l'objet FolderBrowser boite de dialogue
   $TxtBoxDecoupeDossierDestination.Text = $FolderBrowser.SelectedPath;      # récupère la sélection de l'utilisateur
}

$BtnDecoupeChoisirDossier.Add_Click( { OnClick_BtnDecoupeChoisirDossier } );

#
# LblDecoupeDossierDestination
#
$LblDecoupeDossierDestination.AutoSize = $true;
$LblDecoupeDossierDestination.Location = New-Object System.Drawing.Point(16, 64);
$LblDecoupeDossierDestination.Name = "LblDecoupeDossierDestination";
$LblDecoupeDossierDestination.Size = New-Object System.Drawing.Size(152, 20);
$LblDecoupeDossierDestination.TabIndex = 37;
$LblDecoupeDossierDestination.Text = "Dossier Destination:";
#
# TxtBoxDecoupeDossierDestination
#
$TxtBoxDecoupeDossierDestination.Location = New-Object System.Drawing.Point(181, 61);
$TxtBoxDecoupeDossierDestination.Name = "TxtBoxDecoupeDossierDestination";
$TxtBoxDecoupeDossierDestination.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeDossierDestination.TabIndex = 36;
#
# btnDecoupeImage
#
$btnDecoupeImage.Location = New-Object System.Drawing.Point(658, 26);
$btnDecoupeImage.Name = "btnDecoupeImage";
$btnDecoupeImage.Size = New-Object System.Drawing.Size(136, 53);
$btnDecoupeImage.TabIndex = 33;
$btnDecoupeImage.Text = "Découpe Image";
$btnDecoupeImage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet le découpage d'une image Wim suivant une taille choisit par l'utilisateur
###########################################################################################################################

function OnClick_btnDecoupeImage{
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement btnDecoupeImage.Add_Click n'est pas implémenté.");
  
  $StrDISMArguments = "/Split-Image /ImageFile:" + "`"" + $TxtBoxDecoupeFichierWIM.Text + "`"" + " /SWMFile:" + "`"" + $TxtBoxDecoupeDossierDestination.Text + "\" + $TxtBoxDecoupeFichierSWM.Text + "`"" + " /FileSize:" + [System.Uint64]$TxtBoxDecoupeTailleFichier.Text;
  if ($ChkBoxDecoupeCheckIntegrity.Checked -eq $true){
     $StrDISMArguments = $StrDISMArguments + " /CheckIntegrity";
  }
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
  write-host "OnClick_btnDecoupeImage (avant), contenu de la variable: "$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
  write-host "OnClick_btnDecoupeImage (après), contenu de la variable: "$global:StrOutput;
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
}

$btnDecoupeImage.Add_Click( { OnClick_btnDecoupeImage } );

#
# ChkBoxDecoupeCheckIntegrity
#
$ChkBoxDecoupeCheckIntegrity.AutoSize = $true;
$ChkBoxDecoupeCheckIntegrity.Location = New-Object System.Drawing.Point(501, 134);
$ChkBoxDecoupeCheckIntegrity.Name = "ChkBoxDecoupeCheckIntegrity";
$ChkBoxDecoupeCheckIntegrity.Size = New-Object System.Drawing.Size(134, 24);
$ChkBoxDecoupeCheckIntegrity.TabIndex = 32;
$ChkBoxDecoupeCheckIntegrity.Text = "/CheckIntegrity";
$ChkBoxDecoupeCheckIntegrity.UseVisualStyleBackColor = $true;
#
# LblDecoupeTailleFichier
#
$LblDecoupeTailleFichier.AutoSize = $true;
$LblDecoupeTailleFichier.Location = New-Object System.Drawing.Point(16, 128);
$LblDecoupeTailleFichier.Name = "LblDecoupeTailleFichier";
$LblDecoupeTailleFichier.Size = New-Object System.Drawing.Size(136, 20);
$LblDecoupeTailleFichier.TabIndex = 31;
$LblDecoupeTailleFichier.Text = "Taille Fichier (Mo):";
#
# TxtBoxDecoupeTailleFichier
#
$TxtBoxDecoupeTailleFichier.Location = New-Object System.Drawing.Point(181, 125);
$TxtBoxDecoupeTailleFichier.Name = "TxtBoxDecoupeTailleFichier";
$TxtBoxDecoupeTailleFichier.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeTailleFichier.TabIndex = 30;
#
# LblDecoupeNomFichierSWM
#
$LblDecoupeNomFichierSWM.AutoSize = $true;
$LblDecoupeNomFichierSWM.Location = New-Object System.Drawing.Point(16, 96);
$LblDecoupeNomFichierSWM.Name = "LblDecoupeNomFichierSWM";
$LblDecoupeNomFichierSWM.Size = New-Object System.Drawing.Size(140, 20);
$LblDecoupeNomFichierSWM.TabIndex = 29;
$LblDecoupeNomFichierSWM.Text = "Nom Fichier SWM:";
#
# LblDecoupeFichierWim
#
$LblDecoupeFichierWim.AutoSize = $true;
$LblDecoupeFichierWim.Location = New-Object System.Drawing.Point(16, 29);
$LblDecoupeFichierWim.Name = "LblDecoupeFichierWim";
$LblDecoupeFichierWim.Size = New-Object System.Drawing.Size(134, 20);
$LblDecoupeFichierWim.TabIndex = 28;
$LblDecoupeFichierWim.Text = "Nom Fichier WIM:";
#
# TxtBoxDecoupeFichierSWM
#
$TxtBoxDecoupeFichierSWM.Location = New-Object System.Drawing.Point(181, 93);
$TxtBoxDecoupeFichierSWM.Name = "TxtBoxDecoupeFichierSWM";
$TxtBoxDecoupeFichierSWM.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFichierSWM.TabIndex = 27;
#
# TxtBoxDecoupeFichierWIM
#
$TxtBoxDecoupeFichierWIM.Location = New-Object System.Drawing.Point(181, 26);
$TxtBoxDecoupeFichierWIM.Name = "TxtBoxDecoupeFichierWIM";
$TxtBoxDecoupeFichierWIM.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFichierWIM.TabIndex = 26;
#
# CaptureImageFfu
#
$CaptureImageFfu.Controls.Add($LblCaptureFfu_Description);
$CaptureImageFfu.Controls.Add($TxtBoxCaptureFfu_Description);
$CaptureImageFfu.Controls.Add($LstBoxCaptureFfu_LectLogique);
$CaptureImageFfu.Controls.Add($label18);
$CaptureImageFfu.Controls.Add($LblCaptFfu_Nom);
$CaptureImageFfu.Controls.Add($TxtBoxCaptFfu_Nom);
$CaptureImageFfu.Controls.Add($LblCaptFfu_IDPlateforme);
$CaptureImageFfu.Controls.Add($TxtBoxCaptFfu_IDPlateforme);
$CaptureImageFfu.Controls.Add($label20);
$CaptureImageFfu.Controls.Add($LblCaptFfu_NomFichierDest);
$CaptureImageFfu.Controls.Add($LblCaptFfu_DossierDestination);
$CaptureImageFfu.Controls.Add($LblCaptFfu_LecteurPhysique);
$CaptureImageFfu.Controls.Add($CmbBoxCaptureFfu_Compression);
$CaptureImageFfu.Controls.Add($TxtBoxCaptFfu_NomFichierDestination);
$CaptureImageFfu.Controls.Add($TxtBoxCaptFfu_DossierDestination);
$CaptureImageFfu.Controls.Add($TxtBoxCaptFfu_LecteurPhysique);
$CaptureImageFfu.Controls.Add($BtnCaptFfu_Capture);
$CaptureImageFfu.Controls.Add($BtnCaptureFfu_DossierDestination);
$CaptureImageFfu.Controls.Add($BtnCaptureFfu_ChercheLecteurLogique);
$CaptureImageFfu.Location = New-Object System.Drawing.Point(4, 29);
$CaptureImageFfu.Name = "CaptureImageFfu";
$CaptureImageFfu.Size = New-Object System.Drawing.Size(882, 257);
$CaptureImageFfu.TabIndex = 13;
$CaptureImageFfu.Text = "Capture Image Ffu";
$CaptureImageFfu.UseVisualStyleBackColor = $true;
#
# LblCaptureFfu_Description
#
$LblCaptureFfu_Description.AutoSize = $true;
$LblCaptureFfu_Description.Location = New-Object System.Drawing.Point(49, 183);
$LblCaptureFfu_Description.Name = "LblCaptureFfu_Description";
$LblCaptureFfu_Description.Size = New-Object System.Drawing.Size(93, 20);
$LblCaptureFfu_Description.TabIndex = 37;
$LblCaptureFfu_Description.Text = "Description:";
#
# TxtBoxCaptureFfu_Description
#
$TxtBoxCaptureFfu_Description.Location = New-Object System.Drawing.Point(204, 180);
$TxtBoxCaptureFfu_Description.Name = "TxtBoxCaptureFfu_Description";
$TxtBoxCaptureFfu_Description.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptureFfu_Description.TabIndex = 36;
#
# LstBoxCaptureFfu_LectLogique
#
$LstBoxCaptureFfu_LectLogique.FormattingEnabled = $true;
$LstBoxCaptureFfu_LectLogique.ItemHeight = 20;
$LstBoxCaptureFfu_LectLogique.Location = New-Object System.Drawing.Point(204, 15);
$LstBoxCaptureFfu_LectLogique.Name = "LstBoxCaptureFfu_LectLogique";
$LstBoxCaptureFfu_LectLogique.Size = New-Object System.Drawing.Size(67, 24);
$LstBoxCaptureFfu_LectLogique.TabIndex = 35;

###########################################################################################################################
# Recherche le lecteur physique en fonction du lecteur logique sélectionné, function Capture FFU
###########################################################################################################################

function OnSelectedIndexChanged_LstBoxCaptureFfu_LectLogique {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement LstBoxCaptureFfu_LectLogique.Add_SelectedIndexChanged n'est pas implémenté.");

  $LogicalDiskId = $LstBoxCaptureFfu_LectLogique.SelectedItem; # lecteur logique à traduire
  $DeviceId = "";		        			                   # chaine vide par défaut
  $Query = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='" + $LogicalDiskId + "'} WHERE AssocClass = Win32_LogicalDiskToPartition";
  $QueryResults = [wmisearcher]$Query;
  $Partitions = $QueryResults.Get();                           # récupére l'ensemble des partitions sur le système

  foreach ($Partition in $Partitions){                         # pour chacune des partitions
    $Query="ASSOCIATORS OF {Win32_DiskPartition.DeviceID='" + $Partition["DeviceID"] + "'} WHERE AssocClass = Win32_DiskDriveToDiskPartition";
    $QueryResults = [wmisearcher]$Query;
    $Drives = $QueryResults.Get();
    foreach ($Drive in $Drives){
      $DeviceId = $Drive["DeviceID"].ToString();               # traduire au format \\.\PHYSICALDRIVEx
    }
    $TxtBoxCaptFfu_LecteurPhysique.Text = $DeviceId;
  }
}

$LstBoxCaptureFfu_LectLogique.Add_SelectedIndexChanged( { OnSelectedIndexChanged_LstBoxCaptureFfu_LectLogique } );

#
# label18
#
$label18.AutoSize = $true;
$label18.Location = New-Object System.Drawing.Point(49, 15);
$label18.Name = "label18";
$label18.Size = New-Object System.Drawing.Size(128, 20);
$label18.TabIndex = 34;
$label18.Text = "Lecteur Logique:";
#
# LblCaptFfu_Nom
#
$LblCaptFfu_Nom.AutoSize = $true;
$LblCaptFfu_Nom.Location = New-Object System.Drawing.Point(49, 146);
$LblCaptFfu_Nom.Name = "LblCaptFfu_Nom";
$LblCaptFfu_Nom.Size = New-Object System.Drawing.Size(46, 20);
$LblCaptFfu_Nom.TabIndex = 33;
$LblCaptFfu_Nom.Text = "Nom:";
#
# TxtBoxCaptFfu_Nom
#
$TxtBoxCaptFfu_Nom.Location = New-Object System.Drawing.Point(204, 143);
$TxtBoxCaptFfu_Nom.Name = "TxtBoxCaptFfu_Nom";
$TxtBoxCaptFfu_Nom.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptFfu_Nom.TabIndex = 32;
#
# LblCaptFfu_IDPlateforme
#
$LblCaptFfu_IDPlateforme.AutoSize = $true;
$LblCaptFfu_IDPlateforme.Location = New-Object System.Drawing.Point(49, 215);
$LblCaptFfu_IDPlateforme.Name = "LblCaptFfu_IDPlateforme";
$LblCaptFfu_IDPlateforme.Size = New-Object System.Drawing.Size(111, 20);
$LblCaptFfu_IDPlateforme.TabIndex = 31;
$LblCaptFfu_IDPlateforme.Text = "ID Plateforme:";
#
# TxtBoxCaptFfu_IDPlateforme
#
$TxtBoxCaptFfu_IDPlateforme.Location = New-Object System.Drawing.Point(204, 212);
$TxtBoxCaptFfu_IDPlateforme.Name = "TxtBoxCaptFfu_IDPlateforme";
$TxtBoxCaptFfu_IDPlateforme.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptFfu_IDPlateforme.TabIndex = 30;
$TxtBoxCaptFfu_IDPlateforme.Text = "*";
#
# label20
#
$label20.AutoSize = $true;
$label20.Location = New-Object System.Drawing.Point(517, 212);
$label20.Name = "label20";
$label20.Size = New-Object System.Drawing.Size(106, 20);
$label20.TabIndex = 28;
$label20.Text = "Compression:";
#
# LblCaptFfu_NomFichierDest
#
$LblCaptFfu_NomFichierDest.AutoSize = $true;
$LblCaptFfu_NomFichierDest.Location = New-Object System.Drawing.Point(49, 111);
$LblCaptFfu_NomFichierDest.Name = "LblCaptFfu_NomFichierDest";
$LblCaptFfu_NomFichierDest.Size = New-Object System.Drawing.Size(134, 20);
$LblCaptFfu_NomFichierDest.TabIndex = 27;
$LblCaptFfu_NomFichierDest.Text = "Nom fichier Dest.:";
#
# LblCaptFfu_DossierDestination
#
$LblCaptFfu_DossierDestination.AutoSize = $true;
$LblCaptFfu_DossierDestination.Location = New-Object System.Drawing.Point(49, 79);
$LblCaptFfu_DossierDestination.Name = "LblCaptFfu_DossierDestination";
$LblCaptFfu_DossierDestination.Size = New-Object System.Drawing.Size(149, 20);
$LblCaptFfu_DossierDestination.TabIndex = 26;
$LblCaptFfu_DossierDestination.Text = "Dossier destination:";
#
# LblCaptFfu_LecteurPhysique
#
$LblCaptFfu_LecteurPhysique.AutoSize = $true;
$LblCaptFfu_LecteurPhysique.Location = New-Object System.Drawing.Point(49, 48);
$LblCaptFfu_LecteurPhysique.Name = "LblCaptFfu_LecteurPhysique";
$LblCaptFfu_LecteurPhysique.Size = New-Object System.Drawing.Size(135, 20);
$LblCaptFfu_LecteurPhysique.TabIndex = 25;
$LblCaptFfu_LecteurPhysique.Text = "Lecteur Physique:";
#
# CmbBoxCaptureFfu_Compression
#
$CmbBoxCaptureFfu_Compression.FormattingEnabled = $true;
$CmbBoxCaptureFfu_Compression.Items.AddRange(@(
"default",
"none"))
$CmbBoxCaptureFfu_Compression.Location = New-Object System.Drawing.Point(629, 207);
$CmbBoxCaptureFfu_Compression.Name = "CmbBoxCaptureFfu_Compression";
$CmbBoxCaptureFfu_Compression.Size = New-Object System.Drawing.Size(121, 28);
$CmbBoxCaptureFfu_Compression.TabIndex = 24;
#
# TxtBoxCaptFfu_NomFichierDestination
#
$TxtBoxCaptFfu_NomFichierDestination.Location = New-Object System.Drawing.Point(204, 111);
$TxtBoxCaptFfu_NomFichierDestination.Name = "TxtBoxCaptFfu_NomFichierDestination";
$TxtBoxCaptFfu_NomFichierDestination.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptFfu_NomFichierDestination.TabIndex = 23;
#
# TxtBoxCaptFfu_DossierDestination
#
$TxtBoxCaptFfu_DossierDestination.Location = New-Object System.Drawing.Point(204, 79);
$TxtBoxCaptFfu_DossierDestination.Name = "TxtBoxCaptFfu_DossierDestination";
$TxtBoxCaptFfu_DossierDestination.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptFfu_DossierDestination.TabIndex = 22;
#
# TxtBoxCaptFfu_LecteurPhysique
#
$TxtBoxCaptFfu_LecteurPhysique.Location = New-Object System.Drawing.Point(204, 45);
$TxtBoxCaptFfu_LecteurPhysique.Name = "TxtBoxCaptFfu_LecteurPhysique";
$TxtBoxCaptFfu_LecteurPhysique.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxCaptFfu_LecteurPhysique.TabIndex = 21;
#
# BtnCaptFfu_Capture
#
$BtnCaptFfu_Capture.Location = New-Object System.Drawing.Point(640, 35);
$BtnCaptFfu_Capture.Name = "BtnCaptFfu_Capture";
$BtnCaptFfu_Capture.Size = New-Object System.Drawing.Size(98, 46);
$BtnCaptFfu_Capture.TabIndex = 19;
$BtnCaptFfu_Capture.Text = "Capture";
$BtnCaptFfu_Capture.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet la capture d'une image disque au format Ffu (seules les partitions UEFI sont pris en charge !!)
###########################################################################################################################

function OnClick_BtnCaptFfu_Capture{
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnCaptFfu_Capture.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Capture-Ffu /ImageFile:" + "`"" + $TxtBoxCaptFfu_DossierDestination.Text + "\"+ $TxtBoxCaptFfu_NomFichierDestination.Text + "`"" + " /CaptureDrive:" + "`"" + $TxtBoxCaptFfu_LecteurPhysique.Text + "`"";
  $StrDISMArguments = $StrDISMArguments + " /Name:" + "`"" + $TxtBoxCaptFfu_Nom.Text + "`"" + " /Description:" + "`"" + $TxtBoxCaptureFfu_Description.Text + "`"" + " /PlatformIds:" + "`"" + $TxtBoxCaptFfu_IDPlateforme.Text + "`"";
  $StrDISMArguments = $StrDISMArguments + " /Compress:" + $CmbBoxCaptureFfu_Compression.SelectedItem;
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
  write-host "OnClick_BtnCaptFfu_Capture (avant), contenu de la variable: "$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
  write-host "OnClick_BtnCaptFfu_Capture (après), contenu de la variable: "$global:StrOutput;
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
}

$BtnCaptFfu_Capture.Add_Click( { OnClick_BtnCaptFfu_Capture } );

#
# BtnCaptureFfu_DossierDestination
#
$BtnCaptureFfu_DossierDestination.Location = New-Object System.Drawing.Point(521, 79);
$BtnCaptureFfu_DossierDestination.Name = "BtnCaptureFfu_DossierDestination";
$BtnCaptureFfu_DossierDestination.Size = New-Object System.Drawing.Size(96, 26);
$BtnCaptureFfu_DossierDestination.TabIndex = 18;
$BtnCaptureFfu_DossierDestination.Text = "Parcourir";
$BtnCaptureFfu_DossierDestination.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir le dossier destination d'une capture image Ffu
###########################################################################################################################

function OnClick_BtnCaptureFfu_DossierDestination {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnCaptureFfu_DossierDestination.Add_Click n'est pas implémenté.");

  # définit un objet FolderBrowser
  $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
    RootFolder=[System.Environment+SpecialFolder]'MyComputer'
    SelectedPath = 'C:\'                                                   # à partir du dossier c:\
  }
  [void]$FolderBrowser.ShowDialog();                                         # Affiche l'objet FolderBrowser boite de dialogue
  $TxtBoxCaptFfu_DossierDestination.Text = $FolderBrowser.SelectedPath;      # récupère la sélection de l'utilisateur
}

$BtnCaptureFfu_DossierDestination.Add_Click( { OnClick_BtnCaptureFfu_DossierDestination } );

#
# BtnCaptureFfu_ChercheLecteurLogique
#
$BtnCaptureFfu_ChercheLecteurLogique.Location = New-Object System.Drawing.Point(288, 9);
$BtnCaptureFfu_ChercheLecteurLogique.Name = "BtnCaptureFfu_ChercheLecteurLogique";
$BtnCaptureFfu_ChercheLecteurLogique.Size = New-Object System.Drawing.Size(216, 30);
$BtnCaptureFfu_ChercheLecteurLogique.TabIndex = 17;
$BtnCaptureFfu_ChercheLecteurLogique.Text = "Cherche Lecteur Logique";
$BtnCaptureFfu_ChercheLecteurLogique.UseVisualStyleBackColor = $true;

###########################################################################################################################
# récupérer la liste des lecteurs logiques fonction Capture Ffu
###########################################################################################################################

function OnClick_BtnCaptureFfu_ChercheLecteurLogique {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnCaptureFfu_ChercheLecteurLogique.Add_Click n'est pas implémenté.");

  $LstBoxCaptureFfu_LectLogique.Items.Clear();
  $AllDrives=[System.IO.DriveInfo]::GetDrives();
  foreach ($Drv in $AllDrives){                                               
     $LstBoxCaptureFfu_LectLogique.Items.Add($Drv.Name.Substring(0,($Drv.Name.Length)-1)); # on retire le '\' à la fin de la chaine
  }
}

$BtnCaptureFfu_ChercheLecteurLogique.Add_Click( { OnClick_BtnCaptureFfu_ChercheLecteurLogique } );

#
# AppliqueImageFfu
#
$AppliqueImageFfu.Controls.Add($LstBoxAppliqueImageFfu_LecteurLogique);
$AppliqueImageFfu.Controls.Add($LblAppliqueImageFfu_LecteurLogique);
$AppliqueImageFfu.Controls.Add($label25);
$AppliqueImageFfu.Controls.Add($LblAppliqueImageFfu_FichierSource);
$AppliqueImageFfu.Controls.Add($LblAppliqueImageFfu_LecteurPhysique);
$AppliqueImageFfu.Controls.Add($TxtBoxAppliqueImageFfu_MotifSFUFile);
$AppliqueImageFfu.Controls.Add($TxtBoxAppliqueImageFfu_FichierSourceFfu);
$AppliqueImageFfu.Controls.Add($TxtBoxAppliqueImageFfu_LecteurPhysique);
$AppliqueImageFfu.Controls.Add($BtnAppliqueImageFfu_AppliqueFfu);
$AppliqueImageFfu.Controls.Add($BtnAppliqueImageFfu_ChoisirFichierFfu);
$AppliqueImageFfu.Controls.Add($BtnAppliqueImageFfu_ChercherLecteurLogique);
$AppliqueImageFfu.Location = New-Object System.Drawing.Point(4, 29);
$AppliqueImageFfu.Name = "AppliqueImageFfu";
$AppliqueImageFfu.Size = New-Object System.Drawing.Size(882, 257);
$AppliqueImageFfu.TabIndex = 14;
$AppliqueImageFfu.Text = "Applique Image Ffu";
$AppliqueImageFfu.UseVisualStyleBackColor = $true;
#
# LstBoxAppliqueImageFfu_LecteurLogique
#
$LstBoxAppliqueImageFfu_LecteurLogique.FormattingEnabled = $true;
$LstBoxAppliqueImageFfu_LecteurLogique.ItemHeight = 20;
$LstBoxAppliqueImageFfu_LecteurLogique.Location = New-Object System.Drawing.Point(202, 18);
$LstBoxAppliqueImageFfu_LecteurLogique.Name = "LstBoxAppliqueImageFfu_LecteurLogique";
$LstBoxAppliqueImageFfu_LecteurLogique.Size = New-Object System.Drawing.Size(67, 24);
$LstBoxAppliqueImageFfu_LecteurLogique.TabIndex = 54;

###########################################################################################################################
# Recherche le lecteur physique en fonction du lecteur logique sélectionné, function Applique FFU
###########################################################################################################################

function OnSelectedIndexChanged_LstBoxAppliqueImageFfu_LecteurLogique {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement LstBoxAppliqueImageFfu_LecteurLogique.Add_SelectedIndexChanged n'est pas implémenté.")

  $LogicalDiskId = $LstBoxAppliqueImageFfu_LecteurLogique.SelectedItem; # lecteur logique à traduire
  $DeviceId = "";		        			                           # chaine vide par défaut
  $Query = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='" + $LogicalDiskId + "'} WHERE AssocClass = Win32_LogicalDiskToPartition";
  $QueryResults = [wmisearcher]$Query;
  $Partitions = $QueryResults.Get();                                    # récupére l'ensemble des partitions sur le système

  foreach ($Partition in $Partitions){                                 # pour chacune des partitions
    $Query="ASSOCIATORS OF {Win32_DiskPartition.DeviceID='" + $Partition["DeviceID"] + "'} WHERE AssocClass = Win32_DiskDriveToDiskPartition";
    $QueryResults = [wmisearcher]$Query;
    $Drives = $QueryResults.Get();
    foreach ($Drive in $Drives){
      $DeviceId = $Drive["DeviceID"].ToString();                        # traduire au format \\.\PHYSICALDRIVEx
    }
    $TxtBoxAppliqueImageFfu_LecteurPhysique.Text = $DeviceId;
  }
}

$LstBoxAppliqueImageFfu_LecteurLogique.Add_SelectedIndexChanged( { OnSelectedIndexChanged_LstBoxAppliqueImageFfu_LecteurLogique } );

#
# LblAppliqueImageFfu_LecteurLogique
#
$LblAppliqueImageFfu_LecteurLogique.AutoSize = $true;
$LblAppliqueImageFfu_LecteurLogique.Location = New-Object System.Drawing.Point(47, 18);
$LblAppliqueImageFfu_LecteurLogique.Name = "LblAppliqueImageFfu_LecteurLogique";
$LblAppliqueImageFfu_LecteurLogique.Size = New-Object System.Drawing.Size(128, 20);
$LblAppliqueImageFfu_LecteurLogique.TabIndex = 53;
$LblAppliqueImageFfu_LecteurLogique.Text = "Lecteur Logique:";
#
# label25
#
$label25.AutoSize = $true;
$label25.Location = New-Object System.Drawing.Point(47, 114);
$label25.Name = "label25";
$label25.Size = New-Object System.Drawing.Size(114, 20);
$label25.TabIndex = 47;
$label25.Text = "Motif /SFUFile:";
#
# LblAppliqueImageFfu_FichierSource
#
$LblAppliqueImageFfu_FichierSource.AutoSize = $true;
$LblAppliqueImageFfu_FichierSource.Location = New-Object System.Drawing.Point(47, 82);
$LblAppliqueImageFfu_FichierSource.Name = "LblAppliqueImageFfu_FichierSource";
$LblAppliqueImageFfu_FichierSource.Size = New-Object System.Drawing.Size(143, 20);
$LblAppliqueImageFfu_FichierSource.TabIndex = 46;
$LblAppliqueImageFfu_FichierSource.Text = "Fichier Source Ffu:";
#
# LblAppliqueImageFfu_LecteurPhysique
#
$LblAppliqueImageFfu_LecteurPhysique.AutoSize = $true;
$LblAppliqueImageFfu_LecteurPhysique.Location = New-Object System.Drawing.Point(47, 51);
$LblAppliqueImageFfu_LecteurPhysique.Name = "LblAppliqueImageFfu_LecteurPhysique";
$LblAppliqueImageFfu_LecteurPhysique.Size = New-Object System.Drawing.Size(135, 20);
$LblAppliqueImageFfu_LecteurPhysique.TabIndex = 45;
$LblAppliqueImageFfu_LecteurPhysique.Text = "Lecteur Physique:";
#
# TxtBoxAppliqueImageFfu_MotifSFUFile
#
$TxtBoxAppliqueImageFfu_MotifSFUFile.Location = New-Object System.Drawing.Point(202, 114);
$TxtBoxAppliqueImageFfu_MotifSFUFile.Name = "TxtBoxAppliqueImageFfu_MotifSFUFile";
$TxtBoxAppliqueImageFfu_MotifSFUFile.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxAppliqueImageFfu_MotifSFUFile.TabIndex = 43;
#
# TxtBoxAppliqueImageFfu_FichierSourceFfu
#
$TxtBoxAppliqueImageFfu_FichierSourceFfu.Location = New-Object System.Drawing.Point(202, 82);
$TxtBoxAppliqueImageFfu_FichierSourceFfu.Name = "TxtBoxAppliqueImageFfu_FichierSourceFfu";
$TxtBoxAppliqueImageFfu_FichierSourceFfu.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxAppliqueImageFfu_FichierSourceFfu.TabIndex = 42;
#
# TxtBoxAppliqueImageFfu_LecteurPhysique
#
$TxtBoxAppliqueImageFfu_LecteurPhysique.Location = New-Object System.Drawing.Point(202, 48);
$TxtBoxAppliqueImageFfu_LecteurPhysique.Name = "TxtBoxAppliqueImageFfu_LecteurPhysique";
$TxtBoxAppliqueImageFfu_LecteurPhysique.Size = New-Object System.Drawing.Size(300, 26);
$TxtBoxAppliqueImageFfu_LecteurPhysique.TabIndex = 41;
#
# BtnAppliqueImageFfu_AppliqueFfu
#
$BtnAppliqueImageFfu_AppliqueFfu.Location = New-Object System.Drawing.Point(519, 12);
$BtnAppliqueImageFfu_AppliqueFfu.Name = "BtnAppliqueImageFfu_AppliqueFfu";
$BtnAppliqueImageFfu_AppliqueFfu.Size = New-Object System.Drawing.Size(190, 46);
$BtnAppliqueImageFfu_AppliqueFfu.TabIndex = 40;
$BtnAppliqueImageFfu_AppliqueFfu.Text = "Applique Image Ffu";
$BtnAppliqueImageFfu_AppliqueFfu.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet d'appliquer une image Ffu sur un disque physique (UEFI, pas compatible MBR !!)
###########################################################################################################################

function OnClick_BtnAppliqueImageFfu_AppliqueFfu{
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAppliqueImageFfu_AppliqueFfu.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Apply-Ffu /ImageFile:" + "`"" + $TxtBoxAppliqueImageFfu_FichierSourceFfu.Text + "`"" + " /ApplyDrive:" + "`"" + $TxtBoxAppliqueImageFfu_LecteurPhysique.Text + "`"";
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
  write-host "OnClick_BtnAppliqueImageFfu_AppliqueFfu (avant), contenu de la variable: "$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
  write-host "OnClick_BtnAppliqueImageFfu_AppliqueFfu (après), contenu de la variable: "$global:StrOutput;
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
}

$BtnAppliqueImageFfu_AppliqueFfu.Add_Click( { OnClick_BtnAppliqueImageFfu_AppliqueFfu } );

#
# BtnAppliqueImageFfu_ChoisirFichierFfu
#
$BtnAppliqueImageFfu_ChoisirFichierFfu.Location = New-Object System.Drawing.Point(519, 82);
$BtnAppliqueImageFfu_ChoisirFichierFfu.Name = "BtnAppliqueImageFfu_ChoisirFichierFfu";
$BtnAppliqueImageFfu_ChoisirFichierFfu.Size = New-Object System.Drawing.Size(190, 26);
$BtnAppliqueImageFfu_ChoisirFichierFfu.TabIndex = 39;
$BtnAppliqueImageFfu_ChoisirFichierFfu.Text = "Choisir Fichier Ffu";
$BtnAppliqueImageFfu_ChoisirFichierFfu.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir un disque destination qui va recevoir l'image Ffu, fonction Applique Image Ffu
###########################################################################################################################

function OnClick_BtnAppliqueImageFfu_ChoisirFichierFfu {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAppliqueImageFfu_ChoisirFichierFfu.Add_Click n'est pas implémenté.");

  #définit une boite de dialogue
  #
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = 'C:\'
    Title = 'Choisir un fichier Ffu à ouvrir'
    Filter = 'Fichier Ffu (*.Ffu)|*.Ffu|All Files (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxAppliqueImageFfu_FichierSourceFfu.Text = $FileBrowser.FileName;      # Affiche le résultat de la sélection dans le champ TxtFichierWim
    if ($TxtBoxAppliqueImageFfu_FichierSourceFfu.Text -eq ""){
      [void][System.Windows.Forms.MessageBox]::Show("Vous devez sélectionner un fichier Ffu en premier.");
    }
  }
}

$BtnAppliqueImageFfu_ChoisirFichierFfu.Add_Click( { OnClick_BtnAppliqueImageFfu_ChoisirFichierFfu } );

#
# BtnAppliqueImageFfu_ChercherLecteurLogique
#
$BtnAppliqueImageFfu_ChercherLecteurLogique.Location = New-Object System.Drawing.Point(286, 12);
$BtnAppliqueImageFfu_ChercherLecteurLogique.Name = "BtnAppliqueImageFfu_ChercherLecteurLogique";
$BtnAppliqueImageFfu_ChercherLecteurLogique.Size = New-Object System.Drawing.Size(216, 30);
$BtnAppliqueImageFfu_ChercherLecteurLogique.TabIndex = 38;
$BtnAppliqueImageFfu_ChercherLecteurLogique.Text = "Cherche Lecteur Logique";
$BtnAppliqueImageFfu_ChercherLecteurLogique.UseVisualStyleBackColor = $true;

###########################################################################################################################
# récupérer la liste des lecteurs logiques fonction Applique Image Ffu
###########################################################################################################################

function OnClick_BtnAppliqueImageFfu_ChercherLecteurLogique {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnAppliqueImageFfu_ChercherLecteurLogique.Add_Click n'est pas implémenté.");

  $LstBoxAppliqueImageFfu_LecteurLogique.Items.Clear();
  $AllDrives=[System.IO.DriveInfo]::GetDrives();
  foreach ($Drv in $AllDrives){                                               
    $LstBoxAppliqueImageFfu_LecteurLogique.Items.Add($Drv.Name.Substring(0,($Drv.Name.Length)-1)); # on retire le '\' à la fin de la chaine
  }
}

$BtnAppliqueImageFfu_ChercherLecteurLogique.Add_Click( { OnClick_BtnAppliqueImageFfu_ChercherLecteurLogique } );

#
# DecoupeFfu
#
$DecoupeFfu.Controls.Add($BtnDecoupeFfu_ChoisirFichier);
$DecoupeFfu.Controls.Add($BtnDecoupeFfu_ChoisirDossier);
$DecoupeFfu.Controls.Add($LblDecoupeFfu_DossierDestination);
$DecoupeFfu.Controls.Add($TxtBoxDecoupeFfu_DossierDestination);
$DecoupeFfu.Controls.Add($BtnDecoupeFfu_DecoupeImage);
$DecoupeFfu.Controls.Add($ChkBoxDecoupeFfu_CheckIntegrity);
$DecoupeFfu.Controls.Add($LblDecoupeFfu_TailleFichier);
$DecoupeFfu.Controls.Add($TxtBoxDecoupeFfu_TailleFichier);
$DecoupeFfu.Controls.Add($LblDecoupeFfu_NomFichierSFUFile);
$DecoupeFfu.Controls.Add($LblDecoupeFfu_NomFichierFfu);
$DecoupeFfu.Controls.Add($TxtBoxDecoupeFfu_NomFichierSFU);
$DecoupeFfu.Controls.Add($TxtBoxDecoupeFfu_NomFichierFfu);
$DecoupeFfu.Location = New-Object System.Drawing.Point(4, 29);
$DecoupeFfu.Name = "DecoupeFfu";
$DecoupeFfu.Size = New-Object System.Drawing.Size(882, 257);
$DecoupeFfu.TabIndex = 15;
$DecoupeFfu.Text = "Decoupe Ffu";
$DecoupeFfu.UseVisualStyleBackColor = $true;
#
# BtnDecoupeFfu_ChoisirFichier
#
$BtnDecoupeFfu_ChoisirFichier.Location = New-Object System.Drawing.Point(517, 19);
$BtnDecoupeFfu_ChoisirFichier.Name = "BtnDecoupeFfu_ChoisirFichier";
$BtnDecoupeFfu_ChoisirFichier.Size = New-Object System.Drawing.Size(136, 26);
$BtnDecoupeFfu_ChoisirFichier.TabIndex = 52;
$BtnDecoupeFfu_ChoisirFichier.Text = "Choisir Fichier";
$BtnDecoupeFfu_ChoisirFichier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir le fichier image Ffu à découper
###########################################################################################################################

function OnClick_BtnDecoupeFfu_ChoisirFichier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDecoupeFfu_ChoisirFichier.Add_Click n'est pas implémenté.");

  #définit une boite de dialogue
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{             
    InitialDirectory = 'C:\'
    Title = 'Choisir un fichier Ffu à ouvrir'
    Filter = 'Image Ffu (*.ffu)|*.ffu|Tous Fichiers (*.*)|*.*'
  }
  # Affiche la boite de dialogue
  if ($FileBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
    $TxtBoxDecoupeFfu_NomFichierFfu.Text = $FileBrowser.FileName;      # Affiche le résultat de la sélection dans le champ TxtFichierWim
  }
}

$BtnDecoupeFfu_ChoisirFichier.Add_Click( { OnClick_BtnDecoupeFfu_ChoisirFichier } );

#
# BtnDecoupeFfu_ChoisirDossier
#
$BtnDecoupeFfu_ChoisirDossier.Location = New-Object System.Drawing.Point(517, 57);
$BtnDecoupeFfu_ChoisirDossier.Name = "BtnDecoupeFfu_ChoisirDossier";
$BtnDecoupeFfu_ChoisirDossier.Size = New-Object System.Drawing.Size(136, 26);
$BtnDecoupeFfu_ChoisirDossier.TabIndex = 51;
$BtnDecoupeFfu_ChoisirDossier.Text = "Choisir Dossier";
$BtnDecoupeFfu_ChoisirDossier.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de choisir le dossier ou stocker les fichiers Ffu une fois le découpage réalisé
###########################################################################################################################

function OnClick_BtnDecoupeFfu_ChoisirDossier {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDecoupeFfu_ChoisirDossier.Add_Click n'est pas implémenté.");
  
  # définit un objet FolderBrowser
  $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
    RootFolder=[System.Environment+SpecialFolder]'MyComputer'
    SelectedPath = 'C:\'                                                  # à partir du dossier c:\
  }
  [void]$FolderBrowser.ShowDialog()                                         # Affiche l'objet FolderBrowser boite de dialogue
  $TxtBoxDecoupeFfu_DossierDestination.Text = $FolderBrowser.SelectedPath;  # récupère la sélection de l'utilisateur
}

$BtnDecoupeFfu_ChoisirDossier.Add_Click( { OnClick_BtnDecoupeFfu_ChoisirDossier } );

#
# LblDecoupeFfu_DossierDestination
#
$LblDecoupeFfu_DossierDestination.AutoSize = $true;
$LblDecoupeFfu_DossierDestination.Location = New-Object System.Drawing.Point(47, 57);
$LblDecoupeFfu_DossierDestination.Name = "LblDecoupeFfu_DossierDestination";
$LblDecoupeFfu_DossierDestination.Size = New-Object System.Drawing.Size(152, 20);
$LblDecoupeFfu_DossierDestination.TabIndex = 50;
$LblDecoupeFfu_DossierDestination.Text = "Dossier Destination:";
#
# TxtBoxDecoupeFfu_DossierDestination
#
$TxtBoxDecoupeFfu_DossierDestination.Location = New-Object System.Drawing.Point(200, 54);
$TxtBoxDecoupeFfu_DossierDestination.Name = "TxtBoxDecoupeFfu_DossierDestination";
$TxtBoxDecoupeFfu_DossierDestination.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFfu_DossierDestination.TabIndex = 49;
#
# BtnDecoupeFfu_DecoupeImage
#
$BtnDecoupeFfu_DecoupeImage.Location = New-Object System.Drawing.Point(677, 19);
$BtnDecoupeFfu_DecoupeImage.Name = "BtnDecoupeFfu_DecoupeImage";
$BtnDecoupeFfu_DecoupeImage.Size = New-Object System.Drawing.Size(136, 53);
$BtnDecoupeFfu_DecoupeImage.TabIndex = 48;
$BtnDecoupeFfu_DecoupeImage.Text = "Découpe Image";
$BtnDecoupeFfu_DecoupeImage.UseVisualStyleBackColor = $true;

###########################################################################################################################
# Permet de découper un fichier Ffu suivant une taille donnée
###########################################################################################################################

function OnClick_BtnDecoupeFfu_DecoupeImage {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnDecoupeFfu_DecoupeImage.Add_Click n'est pas implémenté.");

  $StrDISMArguments = "/Split-Ffu /ImageFile:" + "`"" + $TxtBoxDecoupeFfu_NomFichierFfu.Text + "`"" + " /SFUFile:" + "`"" + $TxtBoxDecoupeFfu_DossierDestination.Text + "\" + $TxtBoxDecoupeFfu_NomFichierSFU.Text + "`"" + " /FileSize:" + [System.Uint64]$TxtBoxDecoupeFfu_TailleFichier.Text;
  if ($ChkBoxDecoupeCheckIntegrity.Checked -eq $true){
     $StrDISMArguments = $StrDISMArguments + " /CheckIntegrity";
  }
  $global:StrOutput="Exécution de la ligne de commande: DISM.EXE $StrDISMArguments`r`n";
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
  write-host "OnClick_BtnDecoupeFfu_DecoupeImage (avant), contenu de la variable: "$global:StrOutput;
  OnDoWork_backgroundWorkerDismCommand $StrDISMArguments;
  write-host "OnClick_BtnDecoupeFfu_DecoupeImage (après), contenu de la variable: "$global:StrOutput;
  $TxtBoxOutput.Text = $global:StrOutput;
  $TxtBoxOutput.Refresh();
}

$BtnDecoupeFfu_DecoupeImage.Add_Click( { OnClick_BtnDecoupeFfu_DecoupeImage } );

#
# ChkBoxDecoupeFfu_CheckIntegrity
#
$ChkBoxDecoupeFfu_CheckIntegrity.AutoSize = $true;
$ChkBoxDecoupeFfu_CheckIntegrity.Location = New-Object System.Drawing.Point(520, 127);
$ChkBoxDecoupeFfu_CheckIntegrity.Name = "ChkBoxDecoupeFfu_CheckIntegrity";
$ChkBoxDecoupeFfu_CheckIntegrity.Size = New-Object System.Drawing.Size(134, 24);
$ChkBoxDecoupeFfu_CheckIntegrity.TabIndex = 47;
$ChkBoxDecoupeFfu_CheckIntegrity.Text = "/CheckIntegrity";
$ChkBoxDecoupeFfu_CheckIntegrity.UseVisualStyleBackColor = $true;
#
# LblDecoupeFfu_TailleFichier
#
$LblDecoupeFfu_TailleFichier.AutoSize = $true;
$LblDecoupeFfu_TailleFichier.Location = New-Object System.Drawing.Point(47, 121);
$LblDecoupeFfu_TailleFichier.Name = "LblDecoupeFfu_TailleFichier";
$LblDecoupeFfu_TailleFichier.Size = New-Object System.Drawing.Size(136, 20);
$LblDecoupeFfu_TailleFichier.TabIndex = 46;
$LblDecoupeFfu_TailleFichier.Text = "Taille Fichier (Mo):";
#
# TxtBoxDecoupeFfu_TailleFichier
#
$TxtBoxDecoupeFfu_TailleFichier.Location = New-Object System.Drawing.Point(200, 118);
$TxtBoxDecoupeFfu_TailleFichier.Name = "TxtBoxDecoupeFfu_TailleFichier";
$TxtBoxDecoupeFfu_TailleFichier.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFfu_TailleFichier.TabIndex = 45;
#
# LblDecoupeFfu_NomFichierSFUFile
#
$LblDecoupeFfu_NomFichierSFUFile.AutoSize = $true;
$LblDecoupeFfu_NomFichierSFUFile.Location = New-Object System.Drawing.Point(47, 89);
$LblDecoupeFfu_NomFichierSFUFile.Name = "LblDecoupeFfu_NomFichierSFUFile";
$LblDecoupeFfu_NomFichierSFUFile.Size = New-Object System.Drawing.Size(134, 20);
$LblDecoupeFfu_NomFichierSFUFile.TabIndex = 44;
$LblDecoupeFfu_NomFichierSFUFile.Text = "Nom Fichier SFU:";
#
# LblDecoupeFfu_NomFichierFfu
#
$LblDecoupeFfu_NomFichierFfu.AutoSize = $true;
$LblDecoupeFfu_NomFichierFfu.Location = New-Object System.Drawing.Point(47, 22);
$LblDecoupeFfu_NomFichierFfu.Name = "LblDecoupeFfu_NomFichierFfu";
$LblDecoupeFfu_NomFichierFfu.Size = New-Object System.Drawing.Size(125, 20);
$LblDecoupeFfu_NomFichierFfu.TabIndex = 43;
$LblDecoupeFfu_NomFichierFfu.Text = "Nom Fichier Ffu:";
#
# TxtBoxDecoupeFfu_NomFichierSFU
#
$TxtBoxDecoupeFfu_NomFichierSFU.Location = New-Object System.Drawing.Point(200, 86);
$TxtBoxDecoupeFfu_NomFichierSFU.Name = "TxtBoxDecoupeFfu_NomFichierSFU";
$TxtBoxDecoupeFfu_NomFichierSFU.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFfu_NomFichierSFU.TabIndex = 42;
#
# TxtBoxDecoupeFfu_NomFichierFfu
#
$TxtBoxDecoupeFfu_NomFichierFfu.Location = New-Object System.Drawing.Point(200, 19);
$TxtBoxDecoupeFfu_NomFichierFfu.Name = "TxtBoxDecoupeFfu_NomFichierFfu";
$TxtBoxDecoupeFfu_NomFichierFfu.Size = New-Object System.Drawing.Size(303, 26);
$TxtBoxDecoupeFfu_NomFichierFfu.TabIndex = 41;
#
# TxtBoxOutput
#
$TxtBoxOutput.Location = New-Object System.Drawing.Point(4, 355);
$TxtBoxOutput.Multiline = $true;                                       # mutiline, ne pas oublier
$TxtBoxOutput.Name = "TxtBoxOutput";
$TxtBoxOutput.ScrollBars = [System.Windows.Forms.ScrollBars]::Both;    # bars de scrooling, ne pas oublier
$TxtBoxOutput.Size = New-Object System.Drawing.Size(882, 244);
$TxtBoxOutput.TabIndex = 11;
#
# label1
#
$label1.AutoSize = $true;
$label1.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$label1.Location = New-Object System.Drawing.Point(0, 323);
$label1.Name = "label1";
$label1.Size = New-Object System.Drawing.Size(161, 20);
$label1.TabIndex = 12;
$label1.Text = "Dism (sortie console):";

#
# backgroundWorkerMount
#

function OnDoWork_backgroundWorkerMount {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement backgroundWorkerMount.Add_DoWork n'est pas implémenté.");

  $chkMountReadOnly = $true;                                   # Permet de monter le Wim en lecture seule
  $StrWim = "D:\export\boot.wim";                              # Fichier source à monter
  $StrIndex = 1;                                               # Index à utiliser dans le Wim
  $StrFolderName = "D:\Mount";                                 # Point (ou dossier) de montage du Wim                              

  write-host "Début du montage du Wim...";
  write-host "Contenu de la variable StrWim:$StrWim";          # à vérifier non afficher ? pourquoi ?
  write-host "Contenu de la variable StrIndex:$StrIndex";
  write-host "Contenu de la variable StrFolderName:$StrFolderName";
  write-host "Contenu de la variable chkMountReadInly:$chkMountReadOnly";

  $StrDISMExitCode = "";
  $Process = New-Object System.Diagnostics.Process; 
  $Process.StartInfo.StandardOutputEncoding= [System.Text.Encoding]::GetEncoding($Host.CurrentCulture.TextInfo.OEMCodePage);
  $Process.StartInfo.RedirectStandardOutput = $true;
  $Process.StartInfo.RedirectStandardError = $true;
  $Process.StartInfo.UseShellExecute = $false;
  $Process.StartInfo.CreateNoWindow = $true;
  $Process.StartInfo.FileName = "DISM.EXE";
  if ($chkMountReadOnly -eq $true){
    $Process.StartInfo.Arguments = "/Mount-Wim /WimFile:$StrWIM /Index:$StrIndex /MountDir:$StrFolderName /ReadOnly";
  }
  else{
    $Process.StartInfo.Arguments = "/Mount-Wim /WimFile:$StrWIM /Index:$StrIndex /MountDir:$StrFolderName";
  }
  Write-host "Exécution de la ligne de commande: DISM.EXE "$Process.StartInfo.Arguments.ToString();
  $Process.Start() | Out-Null;                         # Out-Null évite le retour de True sur la console
  write-host $Process.StandardOutput.ReadToEnd();
  $Process.WaitForExit();
  write-host("Fin du montage du Wim...");
  $Process.Close();
}

$backgroundWorkerMount.Add_DoWork( { OnDoWork_backgroundWorkerMount } );


function OnRunWorkerCompleted_backgroundWorkerMount {
	[void][System.Windows.Forms.MessageBox]::Show("L'évènement backgroundWorkerMount.Add_RunWorkerCompleted n'est pas implémenté.");
}

$backgroundWorkerMount.Add_RunWorkerCompleted( { OnRunWorkerCompleted_backgroundWorkerMount } );

###########################################################################################################################
# backgroundWorkerDismCommand
# Révision: 20/01/2021
###########################################################################################################################
#
function OnDoWork_backgroundWorkerDismCommand{

  Param ([String]$DISMArg)
  #[void][System.Windows.Forms.MessageBox]::Show("L'événement backgroundWorkerDismCommand.Add_DoWork n'est pas implementé.")

  write-host 'DansOnDoWork_backgroundWorkerDismCommand, valeur de $DISMArg:'$DISMArg;
  write-host("DansOnDoWork_backgroundWorkerDismCommand, Début d'exécution de la commande DISM...");
  write-host 'DansOnDoWork_backgroundWorkerDismCommand, valeur avant DISM de $global:StrOutput: '$global:StrOutput;
  $global:StrDISMExitCode = "";					    # Valeur de retour de la commande DISM (sous forme string)
  $Process = New-Object System.Diagnostics.Process;                  # crÃ©ation d'un object process
  $Process.StartInfo.StandardOutputEncoding= [System.Text.Encoding]::GetEncoding($Host.CurrentCulture.TextInfo.OEMCodePage); # force le type d'encodage relatif Ã  la culture de langue
  $Process.StartInfo.RedirectStandardOutput = $true;                 # redirection sortie standard
  $Process.StartInfo.RedirectStandardError = $true;                  # redirection sortie erreur
  $Process.StartInfo.UseShellExecute = $false;                       # pas de shell
  $Process.StartInfo.CreateNoWindow = $true;                         # pas de fenêtre
  $Process.StartInfo.FileName = "DISM.EXE";                          # exécutable DISM.EXE
  $Process.StartInfo.Arguments=$DISMArg;                             # argument ligne de commande DISM
  
  write-host "DansOnDoWork_backgroundWorkerDismCommand, exécution de la ligne de commande: DISM.EXE"$Process.StartInfo.Arguments.ToString();
  $Process.Start();                                                  # |Out-Null évite le retour de True sur la console
  $global:StrOutput=$global:StrOutput+$Process.StandardOutput.ReadToEnd(); 
  #write-host "DansOnDoWork_backgroundWorkerDismCommand:"$global:StrOutput; 
  #write-host $Process.StandardOutput.ReadToEnd();                   # lecture de la sortie standard redirigé
  $Process.WaitForExit();                                            # attendre la fin du processus
  $global:StrOutput=$global:StrOutput+$Process.StandardOutput.ReadToEnd();
  $global:StrDISMExitCode=$Process.ExitCode.ToString();              # Code de retour de DISM
  #$TxtBoxOutput.Text=$TxtBoxOutput.Text+$global:StrOutput;          # Maj informations console DISM-GUI
  write-host 'DansOnDoWork_backgroundWorkerDismCommand, valeur aprés DISM de $global:StrOutput: '$global:StrOutput;
  $Process.Close();                                                  # referme le processus
}

#$backgroundWorkerDismCommand.Add_DoWork( { OnDoWork_backgroundWorkerDismCommand } );


function OnRunWorkerCompleted_backgroundWorkerDismCommand {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement backgroundWorkerDismCommand.Add_RunWorkerCompleted n'est pas implémenté.");
}

$backgroundWorkerDismCommand.Add_RunWorkerCompleted( { OnRunWorkerCompleted_backgroundWorkerDismCommand } );

#
# backgroundWorkerDismount
#

function OnDoWork_backgroundWorkerDismount {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement backgroundWorkerDismount.Add_DoWork n'est pas implémenté.");
}

$backgroundWorkerDismount.Add_DoWork( { OnDoWork_backgroundWorkerDismount } );


function OnRunWorkerCompleted_backgroundWorkerDismount {
	[void][System.Windows.Forms.MessageBox]::Show("L'évènement backgroundWorkerDismount.Add_RunWorkerCompleted n'est pas implémenté.");
}

$backgroundWorkerDismount.Add_RunWorkerCompleted( { OnRunWorkerCompleted_backgroundWorkerDismount } );

#
# BtnEffaceConsoleDism
#
$BtnEffaceConsoleDism.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$BtnEffaceConsoleDism.Location = New-Object System.Drawing.Point(709, 317);
$BtnEffaceConsoleDism.Name = "BtnEffaceConsoleDism";
$BtnEffaceConsoleDism.Size = New-Object System.Drawing.Size(177, 32);
$BtnEffaceConsoleDism.TabIndex = 4;
$BtnEffaceConsoleDism.Text = "Efface console";
$BtnEffaceConsoleDism.UseVisualStyleBackColor = $true;

function OnClick_BtnEffaceConsoleDism {
	#[void][System.Windows.Forms.MessageBox]::Show("L'évènement BtnEffaceConsoleDism.Add_Click n'est pas implémenté.");
  
  $TxtBoxOutput.Text="";
  $global:StrOutput="";
}

$BtnEffaceConsoleDism.Add_Click( { OnClick_BtnEffaceConsoleDism } );

#
# TxtBox_DISMVersion
#
$TxtBox_DISMVersion.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$TxtBox_DISMVersion.Location = New-Object System.Drawing.Point(571, 320);
$TxtBox_DISMVersion.Name = "TxtBox_DISMVersion";
$TxtBox_DISMVersion.Size = New-Object System.Drawing.Size(132, 26);
$TxtBox_DISMVersion.TabIndex = 13;
#
# label10
#
$label10.AutoSize = $true;
$label10.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point, 0);
$label10.Location = New-Object System.Drawing.Point(453, 324);
$label10.Name = "label10";
$label10.Size = New-Object System.Drawing.Size(112, 20);
$label10.TabIndex = 14;
$label10.Text = "DISM Version:";
#
# FormMain
#
$FormMain.ClientSize = New-Object System.Drawing.Size(903, 604);
$FormMain.Controls.Add($label10);
$FormMain.Controls.Add($TxtBox_DISMVersion);
$FormMain.Controls.Add($BtnEffaceConsoleDism);
$FormMain.Controls.Add($label1);
$FormMain.Controls.Add($TxtBoxOutput);
$FormMain.Controls.Add($TabGestion);
$FormMain.Controls.Add($menuStrip1);
$FormMain.MainMenuStrip = $menuStrip1;
$FormMain.Name = "FormMain";
$FormMain.Text = "Interface Graphique pour DISM";

###########################################################################################################################
# Permet de mettre à jour le champs version DISM
###########################################################################################################################

function DismVersion {
  [int]$IdxDebStr;
  [int]$IdxFinStr;
  $StrDISMExitCode = "";

  $Process = New-Object System.Diagnostics.Process; 
  $Process.StartInfo.StandardOutputEncoding= [System.Text.Encoding]::GetEncoding($Host.CurrentCulture.TextInfo.OEMCodePage);
  $Process.StartInfo.RedirectStandardOutput = $true;
  $Process.StartInfo.RedirectStandardError = $true;
  $Process.StartInfo.UseShellExecute = $false;
  $Process.StartInfo.CreateNoWindow = $true;
  $Process.StartInfo.FileName = "DISM.EXE";
             
  $Process.Start();
  $StrOutput = $Process.StandardOutput.ReadToEnd();
  $Process.WaitForExit();

  $StrDISMExitCode = $Process.ExitCode.ToString();
  $IdxDebStr = $StrOutput.IndexOf(": ");                                           # recherche de la première occurence ":"
  $IdxFinStr= $StrOutput.IndexOf("DISM");
  $TxtBox_DISMVersion.Text = $StrOutput.Substring($IdxDebStr+2,$IdxFinStr-($IdxDebStr+2)); # recupère la version
  $Process.Close();
}

###########################################################################################################################
# Evenement sur le chargement de la forme principale
###########################################################################################################################

function OnLoad_FormMain {
  #	[void][System.Windows.Forms.MessageBox]::Show("L'évènement FormMain.Add_Load n'est pas implémenté.");

  DismVersion;                                            # affiche la version de DISM utilisé (par défaut windows et non adk à modifier)
  $CmbBoxCaptureCompression.Text = "Fast";                # niveau de compression FAST pour la capture d'image (par défaut)
}

$FormMain.Add_Load( { OnLoad_FormMain } );

###########################################################################################################################
# Evenement sur fermeture de la forme principale
###########################################################################################################################


function OnFormClosing_FormMain { 

   if ($WIMMounted -eq $true){
      OnClick_BtnDemonterWim;
   }
   
	# $this parameter is equal to the sender (object)
	# $_ is equal to the parameter e (eventarg)

	# The CloseReason property indicates a reason for the closure :
	#   if (($_).CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing)

	#Sets the value indicating that the event should be canceled.
	($_).Cancel= $False;
}

$FormMain.Add_FormClosing( { OnFormClosing_FormMain} );

$FormMain.Add_Shown({$FormMain.Activate()});
$ModalResult=$FormMain.ShowDialog();
# Libération de la Form
$FormMain.Dispose();