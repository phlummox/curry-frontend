
cymake=../dist/build/cymake/cymake

rm -f tmp.txt

echo ================

# delete old files
rm -f -r typeclasses/.curry
rm -f -r typeclasses/modules/.curry

# prepare needed interfaces

$cymake -f -i typeclasses typeclasses/Float.curry typeclasses/Prelude.curry > /dev/null
$cymake -f -i typeclasses/modules typeclasses/modules/Prelude.curry > /dev/null

# do the check # 1

if [ "$1" != "modulesOnly" ]
then

for file in DictTrans1 DictTrans2 DictTrans3 DictTrans4 \
  DictTrans5 DictTrans6 DictTrans7 DictTrans8 DictTrans9 \
  DictTrans10 DictTrans11 DictTrans12 \
  Annot1 Annot2 Annot3 Annot4 Annot5 Annot6 Annot7\
  BugDicts BugDictTrans8 Annot_bug Annot_bug2 Annot_bug3 \
  PropagTest1 PropagTest2 PropagTest3 \
  BugAmbig2 \
  TypeSigsTrans BugTypeSigsTrans BugTypeSigsTrans2 \
  ClassEnv TCC GenElems TCC_Bug \
  Arb NullaryClassMethods \
  TypedExpressions2 DictionaryTypes \
  TestDictType \
  DefaultMethods1 DefaultMethods2 \
  BugClassMethodsVsPredefinedFuncs \
  BugTySigs \
  Example Example2 Example3 \
  DictOrderBug DictOrderBug2 DictOrderBug3 DictOrderBug4 DictOrderBug5 DictOrderBug6 DictOrderBug7 \
  TestMixedDeclGroups TypeSigPattern \
  ImplicBug ExtendedExample \
  QualifiedClassMethods Warnings ExpandClassTySigsTypes ExpandClassTySigs TypeSigProblem ContextRed \
  SelSuperclasses2 SelSuperclasses TestInstances2 TestInstances InstanceConstraints2 \
  TestVarious \
  DataConstructorsBug1 DataConstructorsBug2 \
  ArrowInstances ArbTypeSyn \
  EmptyDicts \
  DerivingClassesInScope
do
  echo $file >> tmp.txt
  $cymake -f -i typeclasses typeclasses/$file.curry 2> stderr.txt 1> stdout.txt || (echo "===================="; echo "| Error in $file.curry:" ; echo "===================="; cat stdout.txt; cat stderr.txt; echo)
done

# do the check # 1 b (errors of type class check component)

for file in checkCorrectTypeVarsInTypeSigs CheckRulesInClass CheckRulesInInstance \
  ClassesInContext ClassMethodSigsContainTypeVar ClassNameInInstance \
  ContextImplication ContextsInClassMethodTypeSigs Cycles directCycle \
  doubleClassMethods duplicateClassNames duplicateInstances InstanceConstraints \
  instanceDataTypeCorrect InstanceTypeVarsDoNotAppearTwice SuperclassInstances \
  typeVarsInInstContext typeVarsInTySigContext TyVarInContext
do
  echo $file >> tmp.txt
  $cymake -f -i typeclasses/TCCheck typeclasses/TCCheck/$file.curry 2> stderr.txt 1> stdout.txt && (echo "===================="; echo "| No error in $file.curry:" ; echo "===================="; cat stdout.txt; cat stderr.txt; echo)
done

fi

# Those files contain type classes with other type vars in methods than
# the type variable of the class and can thus not be checked:

# DictTrans5_orig DictTrans6_orig Annot1_orig
# Annot7_orig TypeSigsTrans_orig BugTypeSigsTrans_orig
# TypedExpressions2_orig


# do the check # 2 (modules system related)

for file in TestClassExports TestClassExports2 TestClassExportsImports \
  TestClassExportsNoExportSpec \
  InstancesExports InstancesExports2 InstancesExportsImports InstancesExportBug InstancesExportBugImports \
  Dependencies1 Dependencies1Imports \
  ClassExportImport ClassExportImport1 ClassExportImport2 ClassExportImport3 ClassExportImport4 \
                    ClassExportImport5 ClassExportImport6 ClassExportImport7 ClassExportImport8 \
  Dependencies2 Dependencies2Import1 Dependencies2Import2 Dependencies2Import3 \
  Dependencies3 Dependencies3Import1 Dependencies3Import2 Dependencies3Import3 \
  HiddenNotHidden HiddenNotHiddenImport \
  DefaultMethods DefaultMethodsImport \
  OpClassFuns OpClassFunsImport \
  HidingClasses HidingClasses2 HidingClasses3 HidingClasses4 HidingClasses5 HidingClassesUse HidingClassesUse2 \
  ExportNonHidden ExportNonHiddenUse \
  SyntaxCheck SyntaxCheckUse SyntaxCheckUse2 SyntaxCheckUse3 SyntaxCheckUse4 SyntaxCheckUse5 \
  TCC TCCUse TCCUse2 TCCUse3 TCCUse4 \
  ClassMethodsExport ClassMethodsExportUse ClassMethodsExportUse2 ClassMethodsExportUse3 ClassMethodsExportUse4 \
                     ClassMethodsExportUse5 ClassMethodsExportUse6 ClassMethodsExportUse7 ClassMethodsExportUse8 \
                     ClassMethodsExportUse9 ClassMethodsExportUse10 ClassMethodsExportUse11 ClassMethodsExportUse12 \
                     ClassMethodsExportUse13 ClassMethodsExportUse14 ClassMethodsExportUse15 \
  ImportStar ImportStarUse ImportStarUse2 ImportStarUse3 \
  OverlappingClassMethods1 OverlappingClassMethods2 OverlappingClassMethods3 OverlappingClassMethods4 \
  OverlappingClassMethodsUse2 OverlappingClassMethodsUse4 OverlappingClassMethodsUse5 \
  RedefineClassesBug \
  ReExport ReExportUse ReExportUse2 \
  ModuleExport1 ModuleExport1Import ModuleExport1Import2 \
  ModuleExport2 ModuleExport2Import \
  ModuleExport3 ModuleExport3Import \
  ModuleExport4 ModuleExport4Import \
  HiddenClasses1 HiddenClasses2 HiddenClasses3 \
  AmbigClassExport1 AmbigClassExport2 \
  QualProblem1 QualProblem2 \
  ConflictHidden1 ConflictHidden2 ConflictHiddenUse ConflictHiddenUse2 \
  MultipleInstancesBug1 MultipleInstancesBug2 MultipleInstancesBugUse \
  ClassUses ClassUsesUse \
  AsImportType AsImport AsImportUse \
  ClassMethodsImportBug ClassMethodsImportBug2 \
  ClassHierarchy ClassHierarchy2 ClassHierarchy3 ClassHierarchy4 \
  ModulesExportInstances ModulesExportInstancesModuleExport ModulesExportInstancesModuleExport2 \
  DiamondInsts1 DiamondInsts2 DiamondInsts3 DiamondInsts4 \
  InstancesHierarchy1 InstancesHierarchy2 InstancesHierarchy3 \
  InstancesHierarchy1b InstancesHierarchy2b InstancesHierarchy3b InstancesHierarchy4b \
  InstancesHierarchy1c InstancesHierarchy2c InstancesHierarchy3c InstancesHierarchy4c \
  OverlappingInstances0 OverlappingInstances1 OverlappingInstances2 OverlappingInstancesUse OverlappingInstancesUse2 \
  OverlappingArrowInstances0 OverlappingArrowInstances1 OverlappingArrowInstances2 OverlappingArrowInstancesUse \
  DuplicateClasses1 DuplicateClasses2 DuplicateClassesUse DuplicateClassesUse2 DuplicateClassesUse3 DuplicateClassesUse4 \
  DuplicateClassesUseB DuplicateClassesUseB2 DuplicateClassesUseB3 \
  DuplicateClassesD1 DuplicateClassesD2 DuplicateClassesD3 DuplicateClassesD4 \
  AsImportBug1 AsImportBug2 AsImportBug3 \
  Arb ArbUse \
  TCPrelude TCPreludeUse List Maybe TCList \
  ArbTypeSyn ArbTypeSynUse \
  HiddenClassMethodsBug1 HiddenClassMethodsBug2 \
  AmbiguousClassMethods1 AmbiguousClassMethods2 \
  DuplicateHiddenClasses1 DuplicateHiddenClasses2 DuplicateHiddenClassesUse \
  InstancesClassInScope1 InstancesClassInScope2
do
  echo $file >> tmp.txt
  $cymake -f -i typeclasses/modules typeclasses/modules/$file.curry 2> stderr.txt 1> stdout.txt || (echo "===================="; echo "| Error in $file.curry:" ; echo "===================="; cat stdout.txt; cat stderr.txt; echo)
done

# do the check # 3 (modules system related, errors)

for file in ClassExportErrors ClassExportImportErrors ClassMethodsExportErr1 ClassMethodsExportErr2 \
  ExportNonHiddenUseErr HidingClassesUseErrs RedefineClassesError SyntaxCheckUseErr \
  OverlappingClassMethodsUse1Err OverlappingClassMethodsUse3Err \
  RedefineClassesBug2Err ModuleExport4ImportErr HiddenClasses2Err HiddenClasses3Err \
  AmbigClassExportUseErr ConflictHiddenUseErr OverlappingInstancesUseErr OverlappingArrowInstancesUseErr \
  DuplicateClassesUse2Err AmbiguousClassMethodsUseErr
do
  echo $file >> tmp.txt
  $cymake -f -i typeclasses/modules typeclasses/modules/$file.curry 2> stderr.txt 1> stdout.txt && (echo "===================="; echo "| No error in $file.curry:" ; echo "===================="; cat stdout.txt; cat stderr.txt; echo)
done

echo `cat tmp.txt | wc -l` files checked
rm tmp.txt
rm stderr.txt
rm stdout.txt

